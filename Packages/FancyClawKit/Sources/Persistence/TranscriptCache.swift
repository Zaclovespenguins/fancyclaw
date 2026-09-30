import Foundation
import GatewayProtocol
import SwiftData

/// Gateway-namespaced cache. Only canonical protocol data is persisted; credentials and media bytes are excluded.
@MainActor public final class TranscriptCache {
    public let container: ModelContainer
    private let context: ModelContext
    public let gateway: String

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([CachedSession.self, CachedMessage.self, CachedHistory.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory,
            groupContainer: inMemory ? .none : .identifier(SharedContainer.appGroupIdentifier))
        return try ModelContainer(for: schema, configurations: [config])
    }

    public init(container: ModelContainer, gateway: String) {
        self.container = container; self.context = ModelContext(container); self.gateway = gateway
        context.autosaveEnabled = false
    }

    public func sessions() throws -> [SessionSummary] {
        let gateway = gateway
        return try context.fetch(FetchDescriptor<CachedSession>(predicate: #Predicate { $0.gateway == gateway }))
            .map { try GatewayCoding.decoder().decode(SessionSummary.self, from: $0.payload) }
    }

    public func saveSessions(_ sessions: [SessionSummary], reconcile: Bool = false) throws {
        let gateway = gateway
        let rows = try context.fetch(FetchDescriptor<CachedSession>(predicate: #Predicate { $0.gateway == gateway }))
        let keys = Set(sessions.map(\.key))
        for row in rows where reconcile && !keys.contains(row.key) {
            try deleteSession(row.key)
        }
        for session in sessions {
            let data = try GatewayCoding.encoder().encode(session)
            if let row = rows.first(where: { $0.key == session.key }) { row.payload = data }
            else { context.insert(CachedSession(gateway: gateway, key: session.key, payload: data)) }
        }
        try context.save()
    }

    public func history(_ key: String) throws -> ChatHistoryPage? {
        let gateway = gateway
        let metadata = try context.fetch(FetchDescriptor<CachedHistory>(predicate: #Predicate {
            $0.gateway == gateway && $0.sessionKey == key
        })).first
        guard let metadata else { return nil }
        var page = try GatewayCoding.decoder().decode(ChatHistoryPage.self, from: metadata.payload)
        page.messages = try context.fetch(FetchDescriptor<CachedMessage>(predicate: #Predicate {
            $0.gateway == gateway && $0.sessionKey == key
        }, sortBy: [SortDescriptor(\.position)]))
            .map { try GatewayCoding.decoder().decode(ChatMessage.self, from: $0.payload) }
        return page
    }

    public func saveHistory(_ page: ChatHistoryPage) throws {
        let gateway = gateway
        let key = page.sessionKey
        let rows = try context.fetch(FetchDescriptor<CachedMessage>(predicate: #Predicate {
            $0.gateway == gateway && $0.sessionKey == key
        }))
        let ids = Set(page.messages.map { gateway + "|" + key + "|" + $0.historyIdentity })
        for row in rows where !ids.contains(row.id) { context.delete(row) }
        for (position, message) in page.messages.enumerated() {
            var safe = message
            // Preserve media references, never inline/unknown producer payloads that might carry bytes.
            safe.content = safe.content.compactMap { block in
                switch block {
                case .unknown: return nil
                case .media(var media):
                    if media.url?.hasPrefix("data:") == true { media.url = nil }
                    return .media(media)
                default: return block
                }
            }
            let data = try GatewayCoding.encoder().encode(safe)
            let id = gateway + "|" + key + "|" + message.historyIdentity
            if let row = rows.first(where: { $0.id == id }) { row.payload = data; row.position = position }
            else { context.insert(CachedMessage(gateway: gateway, sessionKey: key,
                entryID: message.historyIdentity, position: position, payload: data)) }
        }
        var metadata = page
        metadata.messages = []
        let data = try GatewayCoding.encoder().encode(metadata)
        let existing = try context.fetch(FetchDescriptor<CachedHistory>(predicate: #Predicate {
            $0.gateway == gateway && $0.sessionKey == key
        })).first
        if let existing { existing.payload = data }
        else { context.insert(CachedHistory(gateway: gateway, sessionKey: key, payload: data)) }
        try context.save()
    }

    public func deleteHistory(_ key: String) throws {
        let gateway = gateway
        try context.delete(model: CachedMessage.self, where: #Predicate { $0.gateway == gateway && $0.sessionKey == key })
        try context.delete(model: CachedHistory.self, where: #Predicate { $0.gateway == gateway && $0.sessionKey == key })
        try context.save()
    }

    public func deleteSession(_ key: String) throws {
        let gateway = gateway
        try context.delete(model: CachedSession.self, where: #Predicate { $0.gateway == gateway && $0.key == key })
        try deleteHistory(key)
    }
}
