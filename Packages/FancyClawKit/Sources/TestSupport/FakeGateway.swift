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
    }

    private let queue = DispatchQueue(label: "FancyClaw.FakeGateway")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var replies: [Reply]
    private var requests: [ConnectParams] = []
    private var failures: [Error] = []
    private var rpcRequests: [RequestFrame<JSONValue>] = []
    private var chatReply: String?
    private var activeRuns: [String: String] = [:]
    private var rpcReplies: [String: JSONValue] = [:]
    private var queuedRPCReplies: [String: [JSONValue]] = [:]
    private var sessionSupport = false
    private var sessionRows: [SessionSummary] = []
    private var histories: [String: [ChatMessage]] = [:]
    private var cursorVersion = 0

    /// A small stateful session service used only by debug app launches and session integration tests.
    public func enableSessions() {
        lock.withLock {
            sessionSupport = true
            sessionRows = [SessionSummary(key: "agent:main:main", sessionId: "fake-main", agentId: "main", displayName: "Main chat")]
        }
    }

    public func reply(to method: String, withSequence payloads: [JSONValue]) {
        lock.withLock { queuedRPCReplies[method] = payloads }
    }
    public let challenge: ConnectChallenge

    public init(replies: [Reply], challenge: ConnectChallenge = .init(nonce: "fake-nonce", ts: 1_737_264_000_000)) {
        self.replies = replies
        self.challenge = challenge
    }

    public var receivedRequests: [RequestFrame<JSONValue>] { lock.withLock { rpcRequests } }

    public func streamChatReply(_ text: String) { lock.withLock { chatReply = text } }

    public func emit(_ frame: GatewayEventFrame) {
        let peers = lock.withLock { connections }
        for peer in peers { send(frame, on: peer) }
    }

    public var receivedConnects: [ConnectParams] { lock.withLock { requests } }
    public var recordedFailures: [Error] { lock.withLock { failures } }

    public func reply(to method: String, with payload: JSONValue) {
        lock.withLock { rpcReplies[method] = payload }
    }

    public func start() async throws -> URL {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port else { continuation.resume(throwing: FakeError.noPort); return }
                    continuation.resume(returning: URL(string: "ws://127.0.0.1:\(port.rawValue)/")!)
                case .failed(let error): continuation.resume(throwing: error)
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
            do {
                let request = try GatewayCoding.decoder().decode(RequestFrame<JSONValue>.self, from: data)
                lock.withLock { rpcRequests.append(request) }
                if let scripted = lock.withLock({ () -> JSONValue? in
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
                            histories[sessionKey, default: []].append(ChatMessage(role: .user, content: [.text(request.params?["message"]?.stringValue ?? "")],
                                idempotencyKey: runID, metadata: .init(id: runID + ":user")))
                            cursorVersion += 1
                        }
                    }
                    send(ResponseFrame(id: request.id, ok: true,
                        payload: ChatSendResponse(runId: runID, status: .started)), on: connection)
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
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
                receiveRequest(on: connection)
            } catch { lock.withLock { failures.append(error) } }
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
                let agent = request.params?["agentId"]?.stringValue ?? "main"
                let id = UUID().uuidString
                let row = SessionSummary(key: "agent:\(agent):\(id)", sessionId: id, agentId: agent,
                    updatedAt: Date().timeIntervalSince1970 * 1000)
                sessionRows.insert(row, at: 0)
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
        do {
            let data = try GatewayCoding.encoder().encode(frame)
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
        } catch { lock.withLock { failures.append(error) } }
    }
}
