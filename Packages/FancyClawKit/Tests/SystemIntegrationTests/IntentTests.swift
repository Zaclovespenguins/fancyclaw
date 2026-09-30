import AppIntents
import Foundation
import GatewayProtocol
import Persistence
import SystemIntegration
import SystemActions
import Testing

@Suite("Foreground app intents")
struct IntentTests {
    @Test @MainActor func askReturnsTheInjectedReply() async throws {
        var received: [String] = []
        let service = IntentService(ask: { received.append($0); return "Reply" }, newChat: {}, openSession: { _ in }, sessions: { [] })
        let result = try await AskFancyClawIntent(message: "Question", service: service).perform()
        #expect(result.value == "Reply")
        #expect(received == ["Question"])
        #expect(AskFancyClawIntent.supportedModes == .foreground(.immediate))
    }

    @Test @MainActor func emptyAskDoesNotSend() async {
        var sent = false
        let service = IntentService(ask: { _ in sent = true; return "" }, newChat: {}, openSession: { _ in }, sessions: { [] })
        await #expect(throws: IntentError.self) { try await AskFancyClawIntent(message: " \n", service: service).perform() }
        #expect(!sent)
    }

    @Test @MainActor func newAndOpenUseTheAppService() async throws {
        var created = 0
        var opened: SessionEntity?
        let entity = SessionEntity(gateway: "wss://test", sessionKey: "agent:main:other", title: "Other")
        let service = IntentService(ask: { _ in "" }, newChat: { created += 1 }, openSession: { opened = $0 }, sessions: { [entity] })
        _ = try await NewChatIntent(service: NewChatAction(create: service.newChat)).perform()
        _ = try await OpenSessionIntent(target: entity, service: service).perform()
        #expect(created == 1)
        #expect(opened == entity)
    }

    @Test @MainActor func serviceErrorsPropagate() async {
        let service = IntentService(ask: { _ in throw IntentError.notConnected }, newChat: { throw IntentError.notConnected },
                                    openSession: { _ in throw IntentError.sessionUnavailable }, sessions: { [] })
        await #expect(throws: IntentError.self) { try await AskFancyClawIntent(message: "Ask", service: service).perform() }
        await #expect(throws: IntentError.self) { try await NewChatIntent(service: NewChatAction(create: service.newChat)).perform() }
        let entity = SessionEntity(gateway: "wss://test", sessionKey: "gone", title: "Gone")
        await #expect(throws: IntentError.self) { try await OpenSessionIntent(target: entity, service: service).perform() }
    }

    @Test @MainActor func queryReadsNamespacedCacheAndFiltersArchivedSessions() async throws {
        let container = try TranscriptCache.makeContainer(inMemory: true)
        let cache = TranscriptCache(container: container, gateway: "wss://one")
        try cache.saveSessions([
            .init(key: "main", label: "Café plan", updatedAt: 2),
            .init(key: "old", displayName: "Earlier", updatedAt: 1),
            .init(key: "archived", label: "Hidden", archived: true),
            .init(key: "untitled", updatedAt: 0)
        ])
        try TranscriptCache(container: container, gateway: "wss://two").saveSessions([.init(key: "main", label: "Wrong Gateway")])
        let service = IntentService(ask: { _ in "" }, newChat: {}, openSession: { _ in }, sessions: { try SessionEntity.cached(in: cache) })
        let query = SessionEntityQuery(service: service)
        let suggested = try await query.suggestedEntities()
        #expect(suggested.map(\.title) == ["Café plan", "Earlier", "New chat"])
        #expect(try await query.entities(matching: "cafe").map(\.sessionKey) == ["main"])
        let wrong = SessionEntity(gateway: "wss://two", sessionKey: "main", title: "Wrong")
        let found = try await query.entities(for: [suggested[1].id, wrong.id, "deleted", suggested[0].id])
        #expect(found.map(\.sessionKey) == ["old", "main"])
    }

    @Test @MainActor func suggestionsAreBoundedAndSearchCoversTheWholeCache() async throws {
        let entities = (0..<30).map { SessionEntity(gateway: "wss://test", sessionKey: "key\($0)", title: "Chat \($0)") }
        let service = IntentService(ask: { _ in "" }, newChat: {}, openSession: { _ in }, sessions: { entities })
        let query = SessionEntityQuery(service: service)
        #expect(try await query.suggestedEntities().count == 20)
        #expect(try await query.entities(matching: "key29").map(\.sessionKey) == ["key29"])
    }
}
