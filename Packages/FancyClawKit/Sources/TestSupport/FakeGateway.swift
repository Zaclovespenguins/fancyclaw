import CryptoKit
import Foundation
import GatewayProtocol
import GatewayClient
import Network

/// A loopback WebSocket Gateway for deterministic integration tests.
public final class FakeGateway: @unchecked Sendable {
    public enum Reply: Sendable {
        case hello(HelloOK)
        case failure(GatewayErrorShape)
    }

    public enum FakeError: Error, Sendable {
        case invalidConnect
        case invalidSignature
        case invalidIdentity
        case oversizedFrame
        case noPort
        case stopped
    }

    private let queue = DispatchQueue(label: "FancyClaw.FakeGateway")
    private let lock = NSLock()
    private var listener: NWListener?
    private var stopped = false
    private var connections: [NWConnection] = []
    private var replies: [Reply]
    private var connectionFailure: GatewayErrorShape?
    private var requests: [ConnectParams] = []
    private var failures: [Error] = []
    private var rpcRequests: [RequestFrame<JSONValue>] = []
    private var chatReply: String?
    private var activeRuns: [String: String] = [:]
    private var rpcReplies: [String: JSONValue] = [:]
    private var rpcErrors: [String: GatewayErrorShape] = [:]
    private var approvals: [String: ExecApprovalRequest] = [:]
    private var queuedRPCReplies: [String: [JSONValue]] = [:]
    private var sessionSupport = false
    private var sessionRows: [SessionSummary] = []
    private var sessionCreationResults: [String: (params: JSONValue?, row: SessionSummary)] = [:]
    private var histories: [String: [ChatMessage]] = [:]
    private var cursorVersion = 0
    private var requiresMessageSubscription = false
    private var messageSubscriptions: [ObjectIdentifier: Set<String>] = [:]
    private var pausedResponseMethods: Set<String> = []
    private var heldResponses: [(method: String, data: Data, connection: NWConnection)] = []

    /// Models the session-scoped event routing used by the pinned real Gateway.
    public func enforceMessageSubscriptions() {
        lock.withLock { requiresMessageSubscription = true }
    }

    /// A small stateful session service used only by debug app launches and session integration tests.
    public func enableSessions() {
        lock.withLock {
            sessionSupport = true
            sessionRows = [SessionSummary(key: "agent:main:main", sessionId: "fake-main", agentId: "main", displayName: "Main chat")]
        }
    }

    public func seedSessions(_ rows: [SessionSummary]) { lock.withLock { sessionRows = rows } }

    public func reply(to method: String, withSequence payloads: [JSONValue]) {
        lock.withLock { queuedRPCReplies[method] = payloads }
    }
    public let challenge: ConnectChallenge

    public init(replies: [Reply], challenge: ConnectChallenge = .init(nonce: "fake-nonce", ts: 1_737_264_000_000)) {
        self.replies = replies
        self.challenge = challenge
    }

    public var receivedRequests: [RequestFrame<JSONValue>] { lock.withLock { rpcRequests } }

    public func seedHistory(_ messages: [ChatMessage], sessionKey: String, activeRunID: String? = nil) {
        lock.withLock {
            histories[sessionKey] = messages
            if let activeRunID { activeRuns[activeRunID] = sessionKey }
            cursorVersion += 1
        }
    }

    public func streamChatReply(_ text: String) { lock.withLock { chatReply = text } }

    public func emit(_ frame: GatewayEventFrame) {
        emitWireFrame(frame)
    }

    /// Accept untyped wire fixtures too, so regressions don't depend on the client's payload models.
    public func emitWireFrame<T: Encodable & Sendable>(_ frame: T) {
        let peers = lock.withLock { connections }
        for peer in peers { send(frame, on: peer) }
    }

    public var receivedConnects: [ConnectParams] { lock.withLock { requests } }
    public var recordedFailures: [Error] { lock.withLock { failures } }

    public func reply(to method: String, with payload: JSONValue) {
        lock.withLock { rpcReplies[method] = payload }
    }

    public func fail(_ method: String, with error: GatewayErrorShape) {
        lock.withLock { rpcErrors[method] = error }
    }

    public func clearFailure(for method: String) { lock.withLock { _ = rpcErrors.removeValue(forKey: method) } }

    /// A controlled response gate for outbox/acknowledgment races; requests continue to be processed.
    public func pauseResponses(to method: String) { lock.withLock { _ = pausedResponseMethods.insert(method) } }
    public func resumeResponses(to method: String) {
        let responses = lock.withLock {
            pausedResponseMethods.remove(method)
            let responses = heldResponses.filter { $0.method == method }
            heldResponses.removeAll { $0.method == method }
            return responses
        }
        for response in responses { sendData(response.data, on: response.connection) }
    }

    /// Refuses every connection until cleared, without consuming the scripted hello replies.
    public func refuseConnections(_ error: GatewayErrorShape?) {
        lock.withLock { connectionFailure = error }
    }

    public func requestApproval(_ request: ExecApprovalRequest) {
        lock.withLock { approvals[request.id] = request }
        emit(.init(event: .execApprovalRequested(request)))
    }

    public func start() async throws -> URL {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        let listener = try NWListener(using: parameters, on: .any)
        // A stop() that raced ahead of start() must not leave a live listener or a hung continuation.
        guard lock.withLock({ () -> Bool in
            guard !stopped else { return false }
            self.listener = listener
            return true
        }) else { throw FakeError.stopped }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            // NWListener can report several states; the continuation may only be resumed once.
            let once = ResumeOnce(continuation)
            let resume = { @Sendable (result: Result<URL, Error>) in once.resume(with: result) }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port else { resume(.failure(FakeError.noPort)); return }
                    resume(.success(URL(string: "ws://127.0.0.1:\(port.rawValue)/")!))
                case .failed(let error): resume(.failure(error))
                case .cancelled: resume(.failure(FakeError.stopped))
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func dropConnections() {
        lock.withLock {
            for connection in connections { connection.cancel() }
            connections.removeAll()
            activeRuns.removeAll()
        }
    }

    public func stop() {
        let listener = lock.withLock { () -> NWListener? in
            stopped = true
            return self.listener
        }
        listener?.cancel()
        lock.withLock {
            for connection in connections { connection.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.send(EventFrame(event: GatewayEvent.Name.connectChallenge,
                                      payload: self?.challenge), on: connection)
                self?.receiveConnect(on: connection)
            }
        }
        connection.start(queue: queue)
    }

    private func receiveConnect(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error { self.lock.withLock { self.failures.append(error) }; return }
            guard let data else { return }
            do {
                guard data.count <= 64 * 1024 else { throw FakeError.oversizedFrame }
                let request = try GatewayCoding.decoder().decode(RequestFrame<ConnectParams>.self, from: data)
                guard request.method == "connect", let params = request.params,
                      params.client.id == .iOSApp, params.client.mode == .ui,
                      params.role == .operator else { throw FakeError.invalidConnect }
                try verify(params)
                let reply = lock.withLock { () -> Reply? in
                    requests.append(params)
                    if let connectionFailure { return .failure(connectionFailure) }
                    return replies.isEmpty ? nil : replies.removeFirst()
                }
                guard let reply else { throw FakeError.invalidConnect }
                switch reply {
                case .hello(let hello): send(ResponseFrame(id: request.id, ok: true, payload: hello), on: connection)
                case .failure(let failure):
                    send(ResponseFrame<HelloOK>(id: request.id, ok: false, error: failure), on: connection)
                }
                receiveRequest(on: connection)
            } catch {
                lock.withLock { failures.append(error) }
                connection.cancel()
            }
        }
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error { self.lock.withLock { self.failures.append(error) }; return }
            guard let data else { return }
            var requestID: String?
            do {
                let request = try GatewayCoding.decoder().decode(RequestFrame<JSONValue>.self, from: data)
                requestID = request.id
                lock.withLock { rpcRequests.append(request) }
                if let error = lock.withLock({ rpcErrors[request.method] }) {
                    send(ResponseFrame<JSONValue>(id: request.id, ok: false, error: error), on: connection)
                } else if request.method == "sessions.messages.subscribe", let key = request.params?["key"]?.stringValue {
                    lock.withLock { _ = messageSubscriptions[ObjectIdentifier(connection), default: []].insert(key) }
                    send(ResponseFrame(id: request.id, ok: true, payload: JSONValue.object(["subscribed": .bool(true)])), on: connection)
                } else if request.method == "exec.approval.resolve", let params = request.params {
                    let decision = try params.decode(as: ExecApprovalResolveParams.self)
                    let approval = lock.withLock { approvals[decision.id] }
                    if let approval, approval.expiresAt > .now, approval.offeredDecisions.contains(decision.decision) {
                        lock.withLock { _ = approvals.removeValue(forKey: decision.id) }
                        send(ResponseFrame(id: request.id, ok: true, payload: JSONValue.object(["ok": .bool(true)])), on: connection)
                        emit(.init(event: .execApprovalResolved(.init(id: decision.id, decision: decision.decision,
                            resolvedBy: "fake-operator"))))
                    } else {
                        send(ResponseFrame<JSONValue>(id: request.id, ok: false,
                            error: .init(code: .approvalNotFound, message: "Approval already handled or expired")), on: connection)
                    }
                } else if let scripted = lock.withLock({ () -> JSONValue? in
                    guard var queue = queuedRPCReplies[request.method], !queue.isEmpty else { return nil }
                    let next = queue.removeFirst()
                    queuedRPCReplies[request.method] = queue
                    return next
                }) {
                    send(ResponseFrame(id: request.id, ok: true, payload: scripted), on: connection)
                } else if let payload = try sessionReply(request) {
                    send(ResponseFrame(id: request.id, ok: true, payload: payload), on: connection)
                } else if request.method == "chat.send", let text = lock.withLock({ chatReply }),
                   let runID = request.params?["idempotencyKey"]?.stringValue,
                   let sessionKey = request.params?["sessionKey"]?.stringValue {
                    lock.withLock {
                        activeRuns[runID] = sessionKey
                        if sessionSupport {
                            let attachments = (try? request.params?["attachments"]?.decode(as: [ChatAttachment].self)) ?? []
                            let media = attachments.map { attachment in
                                ContentBlock.media(.init(kind: attachment.type == "image" ? .image : .file,
                                    mimeType: attachment.mimeType, fileName: attachment.fileName,
                                    width: attachment.width, height: attachment.height, sizeBytes: attachment.sizeBytes))
                            }
                            histories[sessionKey, default: []].append(ChatMessage(role: .user, content: [.text(request.params?["message"]?.stringValue ?? "")] + media,
                                idempotencyKey: runID + ":user", metadata: .init(id: runID + ":user")))
                            cursorVersion += 1
                        }
                    }
                    send(ResponseFrame(id: request.id, ok: true,
                        payload: ChatSendResponse(runId: runID, status: .started)), on: connection)
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        // An abort during the delay removes the run; a real Gateway sends nothing after `aborted`.
                        guard self.lock.withLock({ self.activeRuns[runID] != nil }) else { return }
                        self.send(GatewayEventFrame(event: .chat(ChatEvent(runId: runID,
                            sessionKey: sessionKey, seq: 1, state: .delta(.init(deltaText: text))))), on: connection)
                        try? await Task.sleep(for: .milliseconds(150))
                        guard self.lock.withLock({ self.activeRuns.removeValue(forKey: runID) != nil }) else { return }
                        self.lock.withLock {
                            if self.sessionSupport {
                                self.histories[sessionKey, default: []].append(ChatMessage(role: .assistant, content: [.text(text)],
                                    metadata: .init(id: runID + ":assistant", runId: runID)))
                                self.cursorVersion += 1
                            }
                        }
                        self.send(GatewayEventFrame(event: .chat(ChatEvent(runId: runID,
                            sessionKey: sessionKey, seq: 2, state: .final(.init(
                                message: ChatMessage(role: .assistant, content: [.text(text)])))))), on: connection)
                    }
                } else if request.method == "chat.abort" {
                    let runID = request.params?["runId"]?.stringValue
                    let sessionKey = request.params?["sessionKey"]?.stringValue ?? "agent:main:main"
                    let runs = lock.withLock { () -> [String] in
                        let keys = activeRuns.filter { $0.value == sessionKey && (runID == nil || $0.key == runID) }.map(\.key)
                        for key in keys { activeRuns.removeValue(forKey: key) }
                        return keys
                    }
                    send(ResponseFrame(id: request.id, ok: true, payload: JSONValue.object(["ok": .bool(true)])), on: connection)
                    for run in runs {
                        send(GatewayEventFrame(event: .chat(ChatEvent(runId: run, sessionKey: sessionKey,
                            seq: 3, state: .aborted(.init())))), on: connection)
                    }
                } else if let payload = lock.withLock({ rpcReplies[request.method] }) {
                    send(ResponseFrame(id: request.id, ok: true, payload: payload), on: connection)
                }
            } catch {
                // Keep the connection alive: answer the request when its ID is known, and record the failure.
                lock.withLock { failures.append(error) }
                if let requestID {
                    send(ResponseFrame<JSONValue>(id: requestID, ok: false,
                        error: .init(code: .invalidRequest, message: "FakeGateway could not handle request: \(error)")),
                        on: connection)
                }
            }
            receiveRequest(on: connection)
        }
    }

    private func sessionReply(_ request: RequestFrame<JSONValue>) throws -> JSONValue? {
        try lock.withLock {
            guard sessionSupport else { return nil }
            switch request.method {
            case "sessions.subscribe": return .object(["subscribed": .bool(true)])
            case "sessions.list":
                let query = request.params?["search"]?.stringValue ?? ""
                let rows = sessionRows.filter { $0.archived != true && (query.isEmpty || ($0.title ?? "New chat").localizedStandardContains(query)) }
                let offset = request.params?["offset"]?.intValue ?? 0
                let limit = request.params?["limit"]?.intValue ?? 60
                return try JSONValue(encoding: SessionsListResult(sessions: Array(rows.dropFirst(offset).prefix(limit)),
                    hasMore: rows.count > offset + limit, nextOffset: offset + limit))
            case "agents.list": return .object(["defaultId": .string("main"), "agents": .array([
                .object(["id": .string("main"), "name": .string("OpenClaw")]),
                .object(["id": .string("helper"), "name": .string("Helper")])])])
            case "models.list": return .object(["models": .array([.object([
                "id": .string("fake-model"), "name": .string("Fake model"), "provider": .string("test"), "available": .bool(true)])])])
            case "sessions.create":
                let creationKey = request.params?["idempotencyKey"]?.stringValue
                if let creationKey, let existing = sessionCreationResults[creationKey] {
                    guard existing.params == request.params else {
                        throw GatewayErrorShape(code: .invalidRequest, message: "Creation key reused with different parameters")
                    }
                    return .object(["ok": .bool(true), "key": .string(existing.row.key), "sessionId": .string(existing.row.sessionId ?? "")])
                }
                let agent = request.params?["agentId"]?.stringValue ?? "main"
                let id = UUID().uuidString
                let row = SessionSummary(key: "agent:\(agent):\(id)", sessionId: id, agentId: agent,
                    updatedAt: Date().timeIntervalSince1970 * 1000)
                sessionRows.insert(row, at: 0)
                if let creationKey { sessionCreationResults[creationKey] = (request.params, row) }
                return .object(["ok": .bool(true), "key": .string(row.key), "sessionId": .string(id)])
            case "sessions.patch":
                if let index = sessionRows.firstIndex(where: { $0.key == request.params?["key"]?.stringValue }) {
                    if let label = request.params?["label"]?.stringValue { sessionRows[index].label = label }
                    if let model = request.params?["model"]?.stringValue { sessionRows[index].model = model }
                    if let archived = request.params?["archived"]?.boolValue { sessionRows[index].archived = archived }
                }
                return .object(["ok": .bool(true)])
            case "sessions.reset":
                let key = request.params?["key"]?.stringValue ?? ""
                histories[key] = []
                if let index = sessionRows.firstIndex(where: { $0.key == key }) { sessionRows[index].sessionId = UUID().uuidString }
                cursorVersion += 1
                return .object(["ok": .bool(true)])
            case "sessions.delete":
                let key = request.params?["key"]?.stringValue ?? ""
                sessionRows.removeAll { $0.key == key }
                histories.removeValue(forKey: key)
                return .object(["ok": .bool(true)])
            case "chat.history":
                let key = request.params?["sessionKey"]?.stringValue ?? "agent:main:main"
                let history = histories[key] ?? []
                let info = ChatSessionInfo(key: key, hasActiveRun: activeRuns.values.contains(key),
                    activeRunIds: activeRuns.filter { $0.value == key }.map(\.key))
                if request.params?["cursor"] != nil {
                    return try JSONValue(encoding: ChatHistoryCatchUp.delta(.init(messages: history, deltaCursor: "cursor:\(cursorVersion)", sessionInfo: info)))
                }
                return try JSONValue(encoding: ChatHistoryPage(sessionKey: key,
                    sessionId: sessionRows.first(where: { $0.key == key })?.sessionId,
                    messages: history, sessionInfo: info, hasMore: false, deltaCursor: "cursor:\(cursorVersion)"))
            default: return nil
            }
        }
    }

    private func verify(_ params: ConnectParams) throws {
        guard let proof = params.device,
              proof.nonce == challenge.nonce, proof.signedAt == challenge.ts,
              let publicBytes = Base64URL.decode(proof.publicKey),
              let signature = Base64URL.decode(proof.signature) else { throw FakeError.invalidIdentity }
        let expectedID = SHA256.hash(data: publicBytes).map { String(format: "%02x", $0) }.joined()
        guard proof.id == expectedID else { throw FakeError.invalidIdentity }
        let token = params.auth?.token ?? params.auth?.bootstrapToken ?? ""
        let payload = ["v3", proof.id, params.client.id.rawValue, params.client.mode.rawValue,
                       params.role?.rawValue ?? "", params.scopes?.map(\.rawValue).joined(separator: ",") ?? "",
                       String(proof.signedAt), token, proof.nonce,
                       params.client.platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                       (params.client.deviceFamily ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
            .joined(separator: "|")
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
        guard publicKey.isValidSignature(signature, for: Data(payload.utf8)) else { throw FakeError.invalidSignature }
    }

    private func send<T: Encodable>(_ frame: T, on connection: NWConnection) {
        if let frame = frame as? GatewayEventFrame {
            let key: String?
            switch frame.event {
            case .chat(let event): key = event.sessionKey
            case .agent(let event): key = event.sessionKey
            default: key = nil
            }
            if let key, lock.withLock({ requiresMessageSubscription &&
                messageSubscriptions[ObjectIdentifier(connection)]?.contains(key) != true }) { return }
        }
        do {
            let data = try GatewayCoding.encoder().encode(frame)
            let wire = try GatewayCoding.decoder().decode(JSONValue.self, from: data)
            let held = lock.withLock {
                guard wire["type"]?.stringValue == "res", let id = wire["id"]?.stringValue,
                      let method = rpcRequests.last(where: { $0.id == id })?.method,
                      pausedResponseMethods.contains(method) else { return false }
                heldResponses.append((method, data, connection))
                return true
            }
            if !held { sendData(data, on: connection) }
        } catch { lock.withLock { failures.append(error) } }
    }

    private func sendData(_ data: Data, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
}

/// Resumes a continuation at most once, however many listener states arrive.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) { self.continuation = continuation }

    func resume(with result: Result<URL, Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<URL, Error>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}
