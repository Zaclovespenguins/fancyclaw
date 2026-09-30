import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import Persistence
import TestSupport
import Testing

@Suite("History paging and catch-up", .serialized) @MainActor
struct HistoryTests {
    private func message(_ id: String, _ text: String? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, content: [.text(text ?? id)], metadata: .init(id: id))
    }

    @Test func olderPagesDeduplicateAndDoNotRollBackCursor() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        let key = SessionKey.main.rawValue
        fake.reply(to: "chat.history", withSequence: [
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "one", messages: [message("b"), message("c")], hasMore: true, nextOffset: 2, deltaCursor: "new")),
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "one", messages: [message("a"), message("b")], hasMore: false, deltaCursor: "old")),
            try JSONValue(encoding: ChatHistoryCatchUp.delta(.init(messages: [message("c", "updated"), message("d")], deltaCursor: "latest")))
        ])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        let store = ConversationStore(connection: connection, cache: cache)
        await store.refreshHistory()
        await store.loadOlderHistory()
        #expect(store.messages.map(\.id) == ["a", "b", "c"])
        #expect(!store.hasMoreHistory)
        #expect(store.deltaCursor == "new")
        await store.refreshHistory()
        #expect(store.messages.map(\.id) == ["a", "b", "c", "d"])
        #expect(store.messages[2].text == "updated")
        #expect(store.deltaCursor == "latest")
        let requests = fake.receivedRequests.filter { $0.method == "chat.history" }
        #expect(requests[1].params?["offset"]?.intValue == 2)
        #expect(requests[2].params?["cursor"]?.stringValue == "new")
        let reopened = ConversationStore(connection: connection, cache: cache)
        #expect(reopened.messages.map(\.id) == store.messages.map(\.id))
        await connection.disconnect()
    }

    @Test func resetRefetchesTailAndClearsOldCache() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        let key = SessionKey.main.rawValue
        fake.reply(to: "chat.history", withSequence: [
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "old-session", messages: [message("old")], hasMore: true, nextOffset: 100, deltaCursor: "expired")),
            try JSONValue(encoding: ChatHistoryCatchUp.reset),
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "new", messages: [message("replacement")], hasMore: false, deltaCursor: "fresh"))
        ])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        let store = ConversationStore(connection: connection, cache: cache)
        await store.refreshHistory()
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(runId: "old-run", sessionKey: key, seq: 1,
            state: .delta(.init(deltaText: "Stale partial"))))))
        await store.refreshHistory()
        #expect(store.messages.map(\.id) == ["replacement"])
        #expect(store.deltaCursor == "fresh")
        #expect(!store.hasMoreHistory)
        #expect(try cache.history(key)?.messages.map(\.entryId) == ["replacement"])
        #expect(fake.receivedRequests.last?.params?["cursor"] == nil)
        await connection.disconnect()
    }

    @Test func offlineCacheAppearsBeforeAnyRequestAndSurvivesFailure() async throws {
        let connection = GatewayConnection(identity: .generate())
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        try cache.saveHistory(.init(sessionKey: SessionKey.main.rawValue, messages: [message("cached")], deltaCursor: "saved"))
        let store = ConversationStore(connection: connection, cache: cache)
        #expect(store.messages.first?.text == "cached")
        await store.refreshHistory()
        #expect(store.messages.first?.text == "cached")
        #expect(store.deltaCursor == "saved")
        #expect(store.errorMessage != nil)
    }

    @Test func legacyIdentitiesRemainStable() {
        let legacy = ChatMessage(role: .user, content: [.text("old")], timestamp: 123)
        #expect(legacy.historyIdentity == legacy.historyIdentity)
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        store.reconcileHistory([legacy])
        let first = store.messages.first?.id
        store.reconcileHistory([message("older"), legacy])
        #expect(store.messages.last?.id == first)
    }
    @Test func resetDuringPagingRefetchesFromTheTail() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        let key = SessionKey.main.rawValue
        fake.reply(to: "chat.history", withSequence: [
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "old", messages: [message("old")], hasMore: true, nextOffset: 100)),
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "new", messages: [], hasMore: false)),
            try JSONValue(encoding: ChatHistoryPage(sessionKey: key, sessionId: "new", messages: [message("fresh")], hasMore: false, deltaCursor: "new-cursor"))
        ])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = ConversationStore(connection: connection)
        await store.refreshHistory()
        await store.loadOlderHistory()
        for _ in 0..<20 where store.deltaCursor != "new-cursor" { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.messages.map(\.id) == ["fresh"])
        #expect(fake.receivedRequests.last?.params?["offset"] == nil)
        await connection.disconnect()
    }

}
