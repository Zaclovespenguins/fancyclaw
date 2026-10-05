@testable import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import Persistence
import TestSupport
import Testing

/// Regressions for yielded finals, failed sends, history/stream races and concurrent `start()`.
@Suite("Conversation store races", .serialized) @MainActor
struct ConversationRaceTests {
    private func gateway() throws -> FakeGateway {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        return FakeGateway(replies: [.hello(hello)])
    }

    private func chat(_ store: ConversationStore, run: String = "run", seq: Int, _ state: ChatEvent.State) -> GatewayEventFrame {
        GatewayEventFrame(event: .chat(ChatEvent(runId: run, sessionKey: store.sessionKey, seq: seq, state: state)))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
    }

    // MARK: B9

    @Test func concurrentStartDoesNotLeakASubscription() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection, streamingInterval: .zero)
        async let first: Void = store.start()
        async let second: Void = store.start()
        _ = await (first, second)
        store.stopListening()
        fake.emit(chat(store, seq: 1, .delta(.init(deltaText: "leaked"))))
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.messages.isEmpty)
        await connection.disconnect()
    }

    // MARK: B1

    @Test func yieldedFinalKeepsTheRunOpen() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()), streamingInterval: .zero)
        store.receive(chat(store, seq: 1, .delta(.init(deltaText: "Old"))))
        store.receive(chat(store, seq: 2, .final(.init(message: ChatMessage(role: .assistant, content: [.text("Yielded")]), yielded: true))))
        #expect(store.isStreaming)
        #expect(store.messages.last?.text == "Yielded")
        #expect(store.messages.last?.isStreaming == true)

        store.receive(chat(store, seq: 3, .delta(.init(deltaText: "Replacement", replace: true))))
        #expect(store.isStreaming)
        store.receive(chat(store, seq: 4, .final(.init())))
        #expect(!store.isStreaming)
        #expect(store.messages.filter { $0.role == .assistant }.map(\.text) == ["Replacement"])
        #expect(store.messages.last?.isStreaming == false)
    }

    // MARK: B8

    @Test func historyAssistantWithRunIDAdoptsTheStreamingRow() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()), streamingInterval: .zero)
        store.receive(chat(store, run: "R", seq: 1, .delta(.init(deltaText: "partial"))))
        store.reconcileHistory([ChatMessage(role: .assistant, content: [.text("partial")], metadata: .init(runId: "R"))])
        #expect(store.messages.filter { $0.role == .assistant }.count == 1)

        store.receive(chat(store, run: "R", seq: 2, .delta(.init(deltaText: " more"))))
        #expect(store.messages.filter { $0.role == .assistant }.count == 1)
        #expect(store.messages.last?.text == "partial more")
        #expect(store.messages.last?.isStreaming == true)
    }

    // MARK: B7

    @Test func historySnapshotIsAppliedWhileDeltasArrive() async throws {
        let fake = try gateway()
        let key = SessionKey.main.rawValue
        fake.reply(to: "chat.history", withSequence: [try JSONValue(encoding: ChatHistoryPage(
            sessionKey: key, sessionId: "one",
            messages: [ChatMessage(role: .user, content: [.text("earlier")], metadata: .init(id: "u1"))],
            hasMore: false, deltaCursor: "c"))])
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        let store = ConversationStore(connection: connection, cache: cache, streamingInterval: .zero)
        let refresh = Task { await store.refreshHistory() }
        await Task.yield()
        for seq in 1...10 { store.receive(chat(store, seq: seq, .delta(.init(deltaText: "x")))) }
        await refresh.value
        #expect(store.messages.contains { $0.id == "u1" })
        #expect(store.messages.contains { $0.role == .assistant && $0.isStreaming })
        try await Task.sleep(for: .milliseconds(200))
        #expect(fake.receivedRequests.filter { $0.method == "chat.history" }.count <= 2)
        await connection.disconnect()
    }

    // MARK: B2

    private func sendKey(_ fake: FakeGateway, at index: Int) -> String? {
        fake.receivedRequests.filter { $0.method == "chat.send" }[safe: index]?.params?["idempotencyKey"]?.stringValue
    }

    @Test func failedSendIsMarkedAndRetriedWithTheSameKey() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        fake.reply(to: "chat.send", with: try JSONValue(encoding: ChatSendResponse(runId: "server-run", status: .started)))
        let url = try await fake.start()
        let connection = GatewayConnection(identity: .generate())
        // Not connected yet, so the first chat.send fails at the transport.
        let store = ConversationStore(connection: connection, streamingInterval: .zero)
        let accepted = await store.send("hello")
        #expect(accepted)
        #expect(store.messages.first?.deliveryFailed == true)
        #expect(!store.isStreaming)

        _ = try await connection.connect(to: url, token: "test-token")
        await store.retryFailedSends()
        let sends = fake.receivedRequests.filter { $0.method == "chat.send" }
        #expect(sends.count == 1)
        #expect(sends.first?.params?["message"]?.stringValue == "hello")
        #expect(store.messages.first?.deliveryFailed == false)
        #expect(store.messages.filter { $0.role == .user }.count == 1)
        await connection.disconnect()
    }

    @Test func failedSendKeepsItsKeyAcrossRetries() async throws {
        let fake = try gateway()
        fake.fail("chat.send", with: .init(code: .unavailable, message: "boom"))
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection, streamingInterval: .zero)
        await store.send("hello")
        #expect(store.messages.first?.deliveryFailed == true)
        let key = try #require(sendKey(fake, at: 0))
        await store.retry(idempotencyKey: key)
        #expect(sendKey(fake, at: 1) == key)
        #expect(store.messages.first?.deliveryFailed == true)
        await connection.disconnect()
    }

    @Test func refreshResendsOnlyUnconfirmedFailedSends() async throws {
        let fake = try gateway()
        let key = SessionKey.main.rawValue
        defer { fake.stop() }
        let url = try await fake.start()
        let connection = GatewayConnection(identity: .generate())
        let store = ConversationStore(connection: connection, streamingInterval: .zero)
        await store.send("lost")
        await store.send("delivered")
        #expect(store.messages.filter(\.deliveryFailed).count == 2)
        let deliveredKey = store.messages[1].id.replacingOccurrences(of: ":user", with: "")

        _ = try await connection.connect(to: url, token: "test-token")
        // The Gateway already has the second message, so only the first is resent after the snapshot.
        fake.reply(to: "chat.history", withSequence: [try JSONValue(encoding: ChatHistoryPage(
            sessionKey: key, sessionId: "one",
            messages: [ChatMessage(role: .user, content: [.text("delivered")], idempotencyKey: deliveredKey, metadata: .init(id: "canon"))],
            hasMore: false, deltaCursor: "c"))])
        await store.refreshHistory()
        let sends = fake.receivedRequests.filter { $0.method == "chat.send" }
        #expect(sends.count == 1)
        #expect(sends.first?.params?["message"]?.stringValue == "lost")
        #expect(store.messages.filter { $0.role == .user }.map(\.text) == ["delivered", "lost"])
        await connection.disconnect()
    }

    @Test func staleSnapshotDoesNotOverwriteLiveRunState() async throws {
        let fake = try gateway()
        let key = SessionKey.main.rawValue
        fake.reply(to: "chat.history", withSequence: [try JSONValue(encoding: ChatHistoryPage(
            sessionKey: key, sessionId: "one",
            messages: [ChatMessage(role: .user, content: [.text("earlier")], metadata: .init(id: "u1"))],
            sessionInfo: .init(key: key, hasActiveRun: false), hasMore: false, deltaCursor: "c"))])
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection, streamingInterval: .zero)
        var snapshots: [Set<String>] = []
        store.onRunSnapshot = { snapshots.append($0) }
        let refresh = Task { await store.refreshHistory() }
        await Task.yield()
        // A run starts after the snapshot was requested; this bumps the revision like a send does.
        store.receive(chat(store, run: "live", seq: 1, .status(.init(phase: nil))))
        store.receive(chat(store, run: "live", seq: 2, .delta(.init(deltaText: "typing"))))
        await refresh.value
        #expect(store.messages.contains { $0.id == "u1" })
        #expect(store.isStreaming)
        #expect(store.messages.last?.isStreaming == true)
        #expect(!snapshots.contains([]))
        await connection.disconnect()
    }

    @Test(arguments: [nil, ["run"], []] as [[String]?])
    func historyDoesNotReopenACompletedRun(activeRunIDs: [String]?) {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()), streamingInterval: .zero)
        store.receive(chat(store, seq: 1, .delta(.init(deltaText: "Done"))))
        store.receive(chat(store, seq: 2, .final(.init())))
        var snapshots: [Set<String>] = []
        store.onRunSnapshot = { snapshots.append($0) }
        // The Gateway can still report activity while terminal state is being persisted.
        store.applyPage(.init(sessionKey: store.sessionKey, messages: [],
            sessionInfo: .init(key: store.sessionKey, hasActiveRun: true, activeRunIds: activeRunIDs)))
        #expect(!store.isStreaming)
        #expect(store.messages.allSatisfy { !$0.isStreaming })
        #expect(!snapshots.contains(["run"]))
    }

    @Test func historyCanDiscoverAnotherRunAfterCompletion() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()), streamingInterval: .zero)
        store.receive(chat(store, seq: 1, .delta(.init(deltaText: "Done"))))
        store.receive(chat(store, seq: 2, .final(.init())))
        var snapshot: Set<String> = []
        store.onRunSnapshot = { snapshot = $0 }
        store.applyPage(.init(sessionKey: store.sessionKey, messages: [],
            sessionInfo: .init(key: store.sessionKey, hasActiveRun: true, activeRunIds: ["run", "other"])))
        #expect(store.isStreaming)
        #expect(snapshot == ["other"])
        store.receive(chat(store, run: "other", seq: 1, .final(.init())))
        #expect(!store.isStreaming)
    }

    @Test(arguments: ["run", "other"])
    func historyRecoveryUsesTheInFlightRunIdentity(runID: String) {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()), streamingInterval: .zero)
        store.receive(chat(store, seq: 1, .delta(.init(deltaText: "Done"))))
        store.receive(chat(store, seq: 2, .final(.init())))
        var snapshot: Set<String> = []
        store.onRunSnapshot = { snapshot = $0 }
        store.applyPage(.init(sessionKey: store.sessionKey, messages: [],
            sessionInfo: .init(key: store.sessionKey, hasActiveRun: true),
            inFlightRun: ["runId": .string(runID)]))
        #expect(store.isStreaming == (runID == "other"))
        #expect(snapshot == (runID == "other" ? ["other"] : []))
        store.receive(chat(store, run: "other", seq: 1, .final(.init())))
        #expect(!store.isStreaming)
    }

    @Test func booleanOnlyHistoryRecoversInitialActivityAndPreservesAYieldedRun() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()), streamingInterval: .zero)
        let page = ChatHistoryPage(sessionKey: store.sessionKey, messages: [],
            sessionInfo: .init(key: store.sessionKey, hasActiveRun: true))
        store.applyPage(page)
        #expect(store.isStreaming)
        store.receive(chat(store, seq: 1, .delta(.init(deltaText: "Still working"))))
        store.receive(chat(store, seq: 2, .final(.init(yielded: true))))
        store.applyPage(page)
        #expect(store.isStreaming)
        store.receive(chat(store, seq: 3, .final(.init())))
        #expect(!store.isStreaming)
        store.applyPage(page)
        #expect(!store.isStreaming)
    }

    @Test func completedFirstReplyCatchesUpFromEnvelopedHistory() async throws {
        let fake = try gateway()
        let key = "agent:main:new-chat"
        let envelope: JSONValue = ["sessionKey": .string(key), "messageId": "answer", "runId": "run",
            "message": ["role": "assistant", "content": "Done", "__openclaw": ["id": "answer", "runId": "run"]]]
        fake.reply(to: "chat.history", withSequence: [
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "new", messages: [],
                sessionInfo: .init(key: key, hasActiveRun: false), deltaCursor: "before")),
            ["kind": "delta", "deltaCursor": "after", "messages": .array([envelope]),
                "sessionInfo": ["key": .string(key), "hasActiveRun": false, "activeRunIds": []]]
        ])
        fake.reply(to: "chat.send", with: try JSONValue(encoding: ChatSendResponse(runId: "run", status: .started)))
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection, sessionKey: key, streamingInterval: .zero)
        await store.refreshHistory()
        #expect(await store.send("Hello"))
        #expect(store.isStreaming)
        store.receive(chat(store, seq: 1, .delta(.init(deltaText: "Done"))))
        store.receive(chat(store, seq: 2, .final(.init())))
        await store.refreshHistory()
        #expect(store.errorMessage == nil)
        #expect(!store.isStreaming)
        #expect(store.deltaCursor == "after")
        #expect(store.messages.filter { $0.role == .assistant }.map(\.text) == ["Done"])
        #expect(store.messages.first(where: { $0.role == .assistant })?.id == "answer")
        await connection.disconnect()
    }

    @Test func gatewayRejectedSendIsNotAutoResent() async throws {
        let fake = try gateway()
        fake.fail("chat.send", with: .init(code: .invalidRequest, message: "rejected"))
        let key = SessionKey.main.rawValue
        fake.reply(to: "chat.history", withSequence: [
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "one", messages: [], hasMore: false, deltaCursor: "c")),
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "one", messages: [], hasMore: false, deltaCursor: "c"))])
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection, streamingInterval: .zero)
        await store.send("nope")
        #expect(store.messages.first?.deliveryFailed == true)
        await store.refreshHistory()
        await store.refreshHistory()
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 1)
        #expect(store.messages.first?.deliveryFailed == true)
        let id = try #require(sendKey(fake, at: 0))
        await store.retry(idempotencyKey: id)
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 2)
        await connection.disconnect()
    }

    @Test func retryByMessageIDResendsAGatewayRejectedSend() async throws {
        let fake = try gateway()
        fake.fail("chat.send", with: .init(code: .invalidRequest, message: "rejected"))
        fake.reply(to: "chat.history", withSequence: [
            try JSONValue(encoding: ChatHistoryPage(sessionKey: SessionKey.main.rawValue, sessionId: "one", messages: [], hasMore: false, deltaCursor: "c"))])
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection, streamingInterval: .zero)
        await store.send("nope")
        let row = try #require(store.messages.first)
        #expect(row.deliveryFailed)
        // The bulk path skips Gateway-rejected sends; the per-message Retry button must not.
        await store.retryFailedSends()
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 1)
        await store.retry(messageID: row.id)
        let sends = fake.receivedRequests.filter { $0.method == "chat.send" }
        #expect(sends.count == 2)
        #expect(sendKey(fake, at: 0) == sendKey(fake, at: 1))
        await store.retry(messageID: "unknown")
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 2)
        await connection.disconnect()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
