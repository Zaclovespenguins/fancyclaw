import Foundation
import GatewayProtocol
import os

public enum ConnectionError: Error, Sendable {
    case invalidChallenge
    case invalidResponse
    case missingPayload
    case frameTooLarge
    case timedOut
    case disconnected
    case protocolMismatch(Int)
}

public actor GatewayConnection {
    private static let logger = Logger(subsystem: "com.zacisnotacompany.fancyclaw", category: "GatewayConnection")
    private let imageSession: URLSession
    private let externalImageSession: URLSession
    private let session: URLSession
    private let identity: DeviceIdentity
    private let identityStore: (any DeviceTokenStoring)?
    private let timing: GatewayTiming
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var pendingTimeouts: [String: Task<Void, Never>] = [:]
    private var eventContinuations: [UUID: AsyncStream<GatewayEventFrame>.Continuation] = [:]
    private var generation = UUID()
    private var ready = false
    private var messageSubscriptions: Set<String> = []
    private var failures: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var mediaOrigin: URL?
    private var mediaBearer: String?
    public private(set) var policy: HelloOK.Policy?
    public private(set) var grantedScopes: [OperatorScope] = []
    private var maxPayload = 25 * 1024 * 1024

    public init(identity: DeviceIdentity, identityStore: (any DeviceTokenStoring)? = nil,
                session: URLSession = .shared, timing: GatewayTiming = .continuous) {
        self.identity = identity
        self.identityStore = identityStore
        self.timing = timing
        self.session = session
        let imageConfiguration = URLSessionConfiguration.ephemeral
        imageConfiguration.urlCache = nil
        imageConfiguration.httpCookieStorage = nil
        imageConfiguration.protocolClasses = session.configuration.protocolClasses
        imageSession = URLSession(configuration: imageConfiguration, delegate: session.delegate, delegateQueue: nil)
        externalImageSession = URLSession(configuration: imageConfiguration)
    }

    func fetchImage(_ reference: String) async throws -> Data {
        guard let origin = mediaOrigin else { throw ConnectionError.disconnected }
        let url = try ArtifactURLResolver.resolve(reference, gateway: origin)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let isGatewayOrigin = ArtifactURLResolver.isSameOrigin(url, gateway: origin)
        if isGatewayOrigin, let mediaBearer {
            request.setValue("Bearer \(mediaBearer)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let mediaGeneration = generation
        let mediaSession = isGatewayOrigin ? imageSession : externalImageSession
        let (bytes, response) = try await mediaSession.data(for: request, delegate: MediaRedirectDelegate())
        guard mediaGeneration == generation else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.mimeType?.hasPrefix("image/") == true else { throw URLError(.badServerResponse) }
        guard bytes.count <= 25 * 1024 * 1024 else { throw ConnectionError.frameTooLarge }
        return bytes
    }

    public func disconnections() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            failures[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeFailureContinuation(id) }
            }
        }
    }

    private func removeFailureContinuation(_ id: UUID) { failures.removeValue(forKey: id) }

    public func events() -> AsyncStream<GatewayEventFrame> {
        let id = UUID()
        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventContinuation(id) }
            }
        }
    }

    private func removeEventContinuation(_ id: UUID) { eventContinuations.removeValue(forKey: id) }

    /// Local event consumers do not register server-side routing. Keep subscriptions for the
    /// socket lifetime so inactive conversation stores and Live Activities still receive events.
    public func subscribeToSessionMessages(_ key: String) async throws {
        guard ready else { throw ConnectionError.disconnected }
        guard !messageSubscriptions.contains(key) else { return }
        let subscriptionGeneration = generation
        let response: JSONValue = try await request("sessions.messages.subscribe",
            params: SessionKeyParams(key: key), returning: JSONValue.self)
        guard subscriptionGeneration == generation, ready else { throw ConnectionError.disconnected }
        guard response["subscribed"]?.boolValue == true else { throw ConnectionError.invalidResponse }
        messageSubscriptions.insert(key)
    }

    public func connect(
        to url: URL, token: String? = nil, bootstrapToken: String? = nil,
        password: String? = nil, version: String = "1.0.0",
        timeout: Duration = .seconds(15)
    ) async throws -> HelloOK {
        try TransportPolicy.validate(url)
        disconnect()
        let attemptGeneration = generation
        let storedToken = try identityStore?.deviceToken(deviceID: identity.deviceID, role: "operator")
        var selectedToken = token ?? storedToken
        var attempts = 0
        while true {
            attempts += 1
            // A stale attempt must not install its socket over a newer connection's.
            guard attemptGeneration == generation else { throw CancellationError() }
            let task = session.webSocketTask(with: url)
            task.resume()
            socket = task
            do {
                let challengeData = try await receive(task, timeout: timeout)
                let event = try GatewayCoding.decoder().decode(GatewayEventFrame.self, from: challengeData)
                guard case .connectChallenge(let challenge) = event.event else { throw ConnectionError.invalidChallenge }
                let scopes: [OperatorScope] = [.read, .write, .approvals]
                let signedToken = selectedToken ?? bootstrapToken ?? ""
                let proof = try identity.proof(challenge: challenge, scopes: scopes, token: signedToken)
                let client = ClientInfo(id: .iOSApp, displayName: "FancyClaw", version: version,
                                        platform: "ios", deviceFamily: "iPhone",
                                        timeZone: TimeZone.current.identifier, mode: .ui)
                let auth = ConnectAuth(token: selectedToken, bootstrapToken: bootstrapToken, password: password)
                let params = ConnectParams(client: client, role: .operator, scopes: scopes,
                    caps: [.toolEvents, .sessionScopedEvents, .approvals, .execApprovals], auth: auth,
                    locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
                    userAgent: "FancyClaw/\(version) (iOS)", device: proof)
                let request = RequestFrame(method: "connect", params: params)
                let bytes = try GatewayCoding.encoder().encode(request)
                guard bytes.count <= 64 * 1024 else { throw ConnectionError.frameTooLarge }
                try await task.send(.string(String(decoding: bytes, as: UTF8.self)))
                let responseData = try await receive(task, timeout: timeout)
                let response = try GatewayCoding.decoder().decode(ResponseFrame<HelloOK>.self, from: responseData)
                guard response.id == request.id else { throw ConnectionError.invalidResponse }
                if let error = response.error, !response.ok { throw error }
                guard let hello = response.payload else { throw ConnectionError.missingPayload }
                guard hello.protocol == ProtocolVersion.current else { throw ConnectionError.protocolMismatch(hello.protocol) }
                guard attemptGeneration == generation else { throw CancellationError() }
                ready = true
                mediaOrigin = url
                mediaBearer = selectedToken ?? password
                policy = hello.policy
                grantedScopes = hello.auth.scopes
                maxPayload = hello.policy.maxPayload
                if url.scheme == "wss" || url.host == "localhost" || url.host == "127.0.0.1" || url.host == "::1" {
                    let issued = hello.auth.deviceTokens?.first { $0.role == .operator }?.deviceToken
                        ?? hello.auth.deviceToken
                    if let issued {
                        // The connection is already authenticated; a Keychain failure only means the token isn't refreshed.
                        do { try identityStore?.saveDeviceToken(issued, deviceID: identity.deviceID, role: "operator") }
                        catch { Self.logger.error("Could not persist the device token; continuing without refreshing it") }
                    }
                }
                reader = Task { await readLoop(task, generation: attemptGeneration) }
                return hello
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                guard attemptGeneration == generation else { throw CancellationError() }
                socket = nil
                ready = false
                mediaOrigin = nil
                mediaBearer = nil
                policy = nil
                grantedScopes = []
                if let gatewayError = error as? GatewayErrorShape {
                    if gatewayError.detailCode == .authTokenMismatch && gatewayError.canRetryWithDeviceToken,
                       selectedToken != storedToken, let storedToken, attempts < 2 {
                        selectedToken = storedToken
                        continue
                    }
                    if gatewayError.isStartupUnavailable && attempts < 3 {
                        let delay = min(max(gatewayError.retryAfterMs ?? 500, 0), 5_000)
                        try await timing.sleep(.milliseconds(delay))
                        guard attemptGeneration == generation else { throw CancellationError() }
                        continue
                    }
                }
                throw error
            }
        }
    }

    public func request<Params: Codable & Sendable, Payload: Codable & Sendable>(
        _ method: String, params: Params?, returning: Payload.Type,
        timeout: Duration = .seconds(15)
    ) async throws -> Payload {
        guard ready, let socket else { throw ConnectionError.disconnected }
        let frame = RequestFrame(method: method, params: params)
        let data = try GatewayCoding.encoder().encode(frame)
        guard data.count <= maxPayload else { throw ConnectionError.frameTooLarge }
        let id = frame.id
        let responseData: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                register(continuation, id: id, data: data, socket: socket, timeout: timeout)
            }
        } onCancel: {
            Task { await self.failPending(id, error: CancellationError()) }
        }
        let response = try GatewayCoding.decoder().decode(ResponseFrame<Payload>.self, from: responseData)
        guard response.id == frame.id else { throw ConnectionError.invalidResponse }
        if !response.ok {
            if let error = response.error { throw error }
            throw ConnectionError.invalidResponse
        }
        guard let payload = response.payload else { throw ConnectionError.missingPayload }
        return payload
    }

    private func register(_ continuation: CheckedContinuation<Data, Error>, id: String, data: Data,
                          socket: URLSessionWebSocketTask, timeout: Duration) {
        if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
        pending[id] = continuation
        Task {
            do { try await socket.send(.string(String(decoding: data, as: UTF8.self))) }
            catch { self.failPending(id, error: error) }
        }
        let timing = timing
        pendingTimeouts[id] = Task {
            do { try await timing.sleep(timeout) } catch { return }
            self.failPending(id, error: ConnectionError.timedOut)
        }
    }

    private func failPending(_ id: String, error: Error) {
        takePending(id)?.resume(throwing: error)
    }

    /// Removes a pending RPC and cancels its timeout so neither outlives the response.
    private func takePending(_ id: String) -> CheckedContinuation<Data, Error>? {
        pendingTimeouts.removeValue(forKey: id)?.cancel()
        return pending.removeValue(forKey: id)
    }

    private func readLoop(_ task: URLSessionWebSocketTask, generation readerGeneration: UUID) async {
        do {
            while !Task.isCancelled {
                let data = try await receive(task, timeout: .seconds(120))
                guard readerGeneration == generation else { return }
                let header = try GatewayCoding.decoder().decode(FrameHeader.self, from: data)
                switch header.type {
                case .response:
                    if let id = header.id { takePending(id)?.resume(returning: data) }
                case .event:
                    let event: GatewayEventFrame
                    do {
                        event = try GatewayCoding.decoder().decode(GatewayEventFrame.self, from: data)
                    } catch let error as DecodingError {
                        Self.logEventDecodingFailure(error, eventName: header.event ?? "<missing>")
                        throw error
                    }
                    for continuation in eventContinuations.values { continuation.yield(event) }
                default: break
                }
            }
        } catch {
            if error is DecodingError {
                // DecodingError descriptions can include payload values; log only structural details above.
                Self.logger.info("Gateway receive loop ended: frame decoding failed")
            } else {
                Self.logger.info("Gateway receive loop ended: \(String(describing: error), privacy: .public)")
            }
            guard readerGeneration == generation else { return }
            ready = false
            socket = nil
            failPending(error)
            for continuation in failures.values { continuation.yield(()) }
        }
    }

    private static func logEventDecodingFailure(_ error: DecodingError, eventName: String) {
        let kind: String
        let path: [any CodingKey]
        switch error {
        case .keyNotFound(let key, let context):
            kind = "keyNotFound"
            path = context.codingPath + [key]
        case .typeMismatch(_, let context):
            kind = "typeMismatch"
            path = context.codingPath
        case .valueNotFound(_, let context):
            kind = "valueNotFound"
            path = context.codingPath
        case .dataCorrupted(let context):
            kind = "dataCorrupted"
            path = context.codingPath
        @unknown default:
            kind = "unknown"
            path = []
        }
        let fieldPath = path.map(\.stringValue).joined(separator: ".")
        logger.error("Gateway event decoding failed: event=\(eventName, privacy: .public) kind=\(kind, privacy: .public) path=\(fieldPath, privacy: .public)")
    }

    private func receive(_ task: URLSessionWebSocketTask, timeout: Duration) async throws -> Data {
        let message = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await task.receive() }
            group.addTask { try await Task.sleep(for: timeout); throw ConnectionError.timedOut }
            guard let result = try await group.next() else { throw ConnectionError.disconnected }
            group.cancelAll()
            return result
        }
        switch message {
        case .data(let data): return data
        case .string(let string): return Data(string.utf8)
        @unknown default: throw ConnectionError.invalidResponse
        }
    }

    private func failPending(_ error: Error) {
        for timeout in pendingTimeouts.values { timeout.cancel() }
        pendingTimeouts.removeAll()
        for continuation in pending.values { continuation.resume(throwing: error) }
        pending.removeAll()
    }

    public func disconnect() {
        generation = UUID()
        ready = false
        messageSubscriptions.removeAll()
        mediaOrigin = nil
        mediaBearer = nil
        reader?.cancel()
        reader = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        failPending(ConnectionError.disconnected)
    }
}

extension ConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidChallenge, .invalidResponse, .missingPayload: "The Gateway sent an unexpected response."
        case .frameTooLarge: "The message exceeds the Gateway’s size limit."
        case .timedOut: "The Gateway took too long to respond."
        case .disconnected: "The Gateway is disconnected. Reconnect and try again."
        case .protocolMismatch: "This Gateway uses an unsupported protocol version."
        }
    }
}
