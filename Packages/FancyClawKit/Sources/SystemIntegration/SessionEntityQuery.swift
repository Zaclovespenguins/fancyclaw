import AppIntents

public struct SessionEntityQuery: EntityStringQuery {
    @Dependency private var service: IntentService

    public init() {}

    /// Explicit injection supports direct perform() and query tests outside the system intent flow.
    public init(service: IntentService) { self.service = service }

    @MainActor public func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        let rows = try service.sessions()
        return identifiers.compactMap { id in rows.first { $0.id == id } }
    }

    @MainActor public func suggestedEntities() async throws -> [SessionEntity] {
        Array(try service.sessions().prefix(20))
    }

    @MainActor public func entities(matching string: String) async throws -> [SessionEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return try service.sessions().filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || $0.sessionKey.localizedStandardContains(query)
        }
    }
}
