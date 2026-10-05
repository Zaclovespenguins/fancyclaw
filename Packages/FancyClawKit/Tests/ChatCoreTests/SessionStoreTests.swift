import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import Persistence
import TestSupport
import Testing

@Suite("Session store", .serialized) @MainActor
struct SessionStoreTests {
    @Test func messagePhaseRefreshesOrUpsertsWithoutInvalidatingHistory() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        fake.enableSessions()
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        let history = ChatHistoryPage(sessionKey: "agent:main:main",
            messages: [ChatMessage(role: .assistant, content: [.text("Cached reply")])])
        try cache.saveHistory(history)
        let store = SessionStore(connection: connection, cache: cache)
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "sessions-changed-message.event")
        guard case .sessionsChanged(var change) = frame.event else {
            Issue.record("Expected session change"); return
        }
        await store.receive(change)
        #expect(store.sessions.first?.displayName == "Main chat")
        #expect(fake.receivedRequests.last?.method == "sessions.list")
        #expect(store.errorMessage == nil)
        let requestCount = fake.receivedRequests.count
        change.session = SessionSummary(key: "agent:main:main", sessionId: "fake-main", label: "Message updated")
        await store.receive(change)
        #expect(store.sessions.first?.label == "Message updated")
        #expect(fake.receivedRequests.count == requestCount)
        #expect(try cache.history("agent:main:main")?.messages == history.messages)
        await connection.disconnect()
    }

    @Test func createRenameModelResetAndArchiveDeleteRoundTrip() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        fake.enableSessions()
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        let store = SessionStore(connection: connection, cache: cache)
        await store.refresh()
        await store.loadCatalogs()
        #expect(store.sessions.count == 1)
        #expect(store.agents.count == 2)
        store.selectedAgentID = "helper"
        let key = try #require(await store.create())
        let row = try #require(store.sessions.first { $0.key == key })
        #expect(row.agentId == "helper")
        await store.rename(row, label: "Renamed")
        await store.setModel(try #require(store.models.first), for: row)
        #expect(store.sessions.first { $0.key == key }?.model == "test/fake-model")
        // Rename survives later mutations and is written through.
        await store.loadList()
        #expect(store.sessions.first { $0.key == key }?.label == "Renamed")
        try cache.saveHistory(.init(sessionKey: key, messages: [ChatMessage(role: .user, content: [.text("old")])]))
        await store.reset(row)
        #expect(try cache.history(key) == nil)
        let current = try #require(store.sessions.first { $0.key == key })
        await store.delete(current)
        #expect(!store.sessions.contains { $0.key == key })
        #expect(try !cache.sessions().contains { $0.key == key })
        let mutations = fake.receivedRequests.suffix(2)
        #expect(mutations.map(\.method) == ["sessions.patch", "sessions.delete"])
        #expect(mutations.first?.params?["archived"]?.boolValue == true)
        #expect(mutations.last?.params?["archivedOnly"]?.boolValue == true)
        #expect(fake.receivedRequests.first { $0.method == "sessions.subscribe" }?.params == .object([:]))
        store.stop()
        await connection.disconnect()
    }

    @Test func changedEventsUpsertAndIgnoreStaleDelete() async throws {
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        try cache.saveSessions([SessionSummary(key: "s", sessionId: "old", label: "Old")])
        try cache.saveHistory(.init(sessionKey: "s", messages: [ChatMessage(role: .user, content: [.text("old")])]))
        let store = SessionStore(connection: GatewayConnection(identity: .generate()), cache: cache)
        #expect(store.sessions.first?.label == "Old")
        await store.receive(.init(sessionKey: "s", reason: "reset", session: SessionSummary(key: "s", sessionId: "new", label: "New")))
        #expect(store.sessions.first?.label == "New")
        #expect(try cache.history("s") == nil)
        await store.receive(.init(sessionKey: "s", reason: "delete", sessionId: "old"))
        #expect(store.sessions.count == 1)
        await store.receive(.init(sessionKey: "s", reason: "delete", sessionId: "new"))
        #expect(store.sessions.isEmpty)
    }

    @Test func partialRosterDoesNotDeleteUnloadedCacheAndSearchIsLocal() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        fake.reply(to: "sessions.list", withSequence: [
            try JSONValue(encoding: SessionsListResult(sessions: [SessionSummary(key: "a", label: "Alpha")], hasMore: true, nextOffset: 1)),
            try JSONValue(encoding: SessionsListResult(sessions: [SessionSummary(key: "b", label: "Beta")], hasMore: false))
        ])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        try cache.saveSessions([SessionSummary(key: "b", label: "Beta"), SessionSummary(key: "deleted", label: "Deleted elsewhere")])
        let store = SessionStore(connection: connection, cache: cache)
        await store.loadList()
        #expect(try cache.sessions().count == 3)
        await store.loadList(older: true)
        #expect(try cache.sessions().count == 2)
        #expect(store.sessions.count == 2)
        store.search = "beta"
        #expect(store.visibleSessions.map(\.key) == ["b"])
        #expect(fake.receivedRequests.last?.params?["offset"]?.intValue == 1)
        await connection.disconnect()
    }
    @Test func searchFindsUnloadedSessionsWithoutReconcilingTheCache() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        fake.reply(to: "sessions.list", with: try JSONValue(encoding: SessionsListResult(
            sessions: [SessionSummary(key: "remote", label: "Remote match")], hasMore: false)))
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "g")
        try cache.saveSessions([SessionSummary(key: "cached", label: "Cached chat")])
        let store = SessionStore(connection: connection, cache: cache)
        store.search = "remote"
        await store.searchSessions()
        #expect(store.visibleSessions.map(\.key) == ["remote"])
        #expect(fake.receivedRequests.last?.params?["search"]?.stringValue == "remote")
        #expect(try cache.sessions().count == 2)
        store.search = ""
        await store.searchSessions()
        #expect(store.visibleSessions.count == 2)
        await connection.disconnect()
    }

    @Test func subscribedEventsReachTheStore() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        fake.enableSessions()
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SessionStore(connection: connection)
        await store.start()
        await store.refresh()
        fake.emit(GatewayEventFrame(event: .sessionsChanged(.init(sessionKey: "pushed", reason: "create",
            session: SessionSummary(key: "pushed", label: "Pushed chat")))))
        for _ in 0..<20 where !store.sessions.contains(where: { $0.key == "pushed" }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.sessions.contains { $0.key == "pushed" })
        store.stop()
        await connection.disconnect()
    }

    @Test func visiblePaginationRoutesToRosterOrSearchAndKeepsArchivedRowsHidden() async throws {
        let fake = try FakeGateway(replies: [.hello(#require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload))])
        fake.reply(to: "sessions.list", withSequence: [
            try JSONValue(encoding: SessionsListResult(sessions: [SessionSummary(key: "a", label: "Alpha"),
                SessionSummary(key: "archived", label: "Archived", archived: true)], hasMore: true, nextOffset: 2)),
            try JSONValue(encoding: SessionsListResult(sessions: [SessionSummary(key: "b", label: "Beta")], hasMore: false)),
            try JSONValue(encoding: SessionsListResult(sessions: [SessionSummary(key: "remote-1", label: "Remote one")], hasMore: true, nextOffset: 1)),
            try JSONValue(encoding: SessionsListResult(sessions: [SessionSummary(key: "remote-2", label: "Remote two")], hasMore: false))
        ])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SessionStore(connection: connection)
        await store.loadList()
        #expect(store.visibleSessions.map(\.key) == ["a"])
        #expect(store.hasMoreVisibleSessions)
        await store.loadMoreVisibleSessions()
        #expect(store.visibleSessions.map(\.key) == ["a", "b"])
        #expect(!store.hasMoreVisibleSessions)
        store.search = "Remote"
        await store.searchSessions()
        #expect(store.hasMoreVisibleSessions)
        await store.loadMoreVisibleSessions()
        #expect(store.visibleSessions.map(\.key) == ["remote-1", "remote-2"])
        #expect(!store.hasMoreVisibleSessions)
        let requests = fake.receivedRequests.filter { $0.method == "sessions.list" }
        try #require(requests.count == 4)
        #expect(requests.map { $0.params?["offset"]?.intValue } == [0, 2, 0, 1])
        #expect(requests[0].params?["search"] == nil && requests[1].params?["search"] == nil)
        #expect(requests[2].params?["search"]?.stringValue == "Remote" && requests[3].params?["search"]?.stringValue == "Remote")
        store.search = ""
        await store.searchSessions()
        #expect(store.visibleSessions.count == 4)
        await connection.disconnect()
    }

}
