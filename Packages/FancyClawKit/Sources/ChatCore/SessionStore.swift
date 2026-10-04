import Foundation
import GatewayClient
import GatewayProtocol
import Observation
import Persistence

@MainActor @Observable public final class SessionStore {
    public private(set) var sessions: [SessionSummary] = []
    public private(set) var agents: [AgentSummary] = []
    public private(set) var models: [ModelSummary] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = false
    public var errorMessage: String?
    public var search = ""
    public var selectedAgentID: String?
    /// Gateway default, independent of the agent selected in a chat's title menu.
    public private(set) var defaultAgentID: String?
    public var onInvalidatedSession: (@MainActor (String) async -> Void)?
    private let connection: GatewayConnection
    private let cache: TranscriptCache?
    private var eventTask: Task<Void, Never>?
    private var offset: Int?
    private var revision = 0
    private let timing: GatewayTiming
    private var searchResults: [SessionSummary]?
    private var resultsQuery: String?
    private var searchOffset: Int?
    private var searchHasMore = false
    public private(set) var isSearching = false

    public init(connection: GatewayConnection, cache: TranscriptCache? = nil, timing: GatewayTiming = .continuous) {
        self.connection = connection; self.cache = cache; self.timing = timing
        do { sessions = try cache?.sessions() ?? []; sortSessions() }
        catch { errorMessage = "Couldn’t read cached chats. \(error.localizedDescription)" }
    }

    public var visibleSessions: [SessionSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = !query.isEmpty && resultsQuery == query ? searchResults ?? sessions : sessions
        return rows.filter {
            $0.archived != true && (query.isEmpty || ($0.title ?? "New chat").localizedStandardContains(query)
                || ($0.lastMessagePreview ?? "").localizedStandardContains(query))
        }
    }

    public var hasMoreVisibleSessions: Bool {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? hasMore : searchHasMore
    }

    public func searchSessions(older: Bool = false) async {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            resultsQuery = nil
            searchHasMore = false
            return
        }
        do {
            if !older { try await timing.sleep(.milliseconds(250)) }
            guard !Task.isCancelled, search.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            let startRevision = revision
            isSearching = true
            defer { isSearching = false }
            let result: SessionsListResult = try await connection.request("sessions.list",
                params: SessionsListParams.drawer(offset: older ? searchOffset ?? 0 : 0, search: query), returning: SessionsListResult.self)
            guard !Task.isCancelled, search.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            guard startRevision == revision else { return }
            let previous = older && resultsQuery == query ? searchResults ?? [] : []
            var merged = previous
            for row in result.sessions {
                if let index = merged.firstIndex(where: { $0.key == row.key }) { merged[index] = row }
                else { merged.append(row) }
                upsert(row)
            }
            searchResults = merged
            resultsQuery = query
            searchOffset = result.nextOffset
            searchHasMore = result.hasMore == true && result.nextOffset != nil
            try cache?.saveSessions(result.sessions)
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    public func loadMoreVisibleSessions() async {
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await loadList(older: true) }
        else if !isSearching && searchHasMore { await searchSessions(older: true) }
    }

    public func start() async {
        guard eventTask == nil else { return }
        let stream = await connection.events()
        eventTask = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled else { return }
                if case .sessionsChanged(let change) = frame.event { await self?.receive(change) }
            }
        }
    }

    public func stop() { eventTask?.cancel(); eventTask = nil }

    /// Subscriptions are connection-scoped, so restore them on every reconnect.
    public func refresh() async {
        do {
            let _: JSONValue = try await connection.request("sessions.subscribe", params: SessionsListParams(), returning: JSONValue.self)
            await loadList()
        } catch { errorMessage = error.localizedDescription }
    }

    public func loadList(older: Bool = false) async {
        guard !isLoading, !older || hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        let startRevision = revision
        let requestedOffset = older ? offset ?? 0 : 0
        do {
            let result: SessionsListResult = try await connection.request("sessions.list",
                params: SessionsListParams.drawer(offset: requestedOffset), returning: SessionsListResult.self)
            // An event received while fetching must not be overwritten by an older list snapshot.
            guard startRevision == revision else {
                Task { [weak self] in await self?.loadList() }
                return
            }
            if older { for session in result.sessions { upsert(session) } }
            else { sessions = result.sessions }
            hasMore = result.hasMore == true && result.nextOffset != nil && result.nextOffset != requestedOffset
            offset = result.nextOffset
            sortSessions()
            // Only the complete roster can establish which cached sessions were deleted.
            try cache?.saveSessions(sessions, reconcile: !hasMore)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    public func loadCatalogs() async {
        do {
            let result: AgentsListResult = try await connection.request("agents.list", params: JSONValue.object([:]), returning: AgentsListResult.self)
            agents = result.agents
            defaultAgentID = result.defaultId
            if selectedAgentID == nil { selectedAgentID = result.defaultId ?? agents.first?.id }
            let catalog: ModelsListResult = try await connection.request("models.list", params: ModelsListParams(), returning: ModelsListResult.self)
            models = catalog.models
        } catch { errorMessage = error.localizedDescription }
    }

    public func create() async -> String? {
        await create(agentID: selectedAgentID)
    }

    /// Explicit nil omits agentId, letting the Gateway choose its default.
    public func create(agentID: String?, idempotencyKey: String = UUID().uuidString) async -> String? {
        do {
            let result: SessionsCreateResult = try await connection.request("sessions.create",
                params: SessionsCreateParams(agentId: agentID, idempotencyKey: idempotencyKey), returning: SessionsCreateResult.self)
            revision += 1
            let row = SessionSummary(key: result.key, sessionId: result.sessionId, agentId: agentID,
                updatedAt: Date().timeIntervalSince1970 * 1000)
            upsert(row)
            errorMessage = nil
            do { try cache?.saveSessions([row]) }
            catch { errorMessage = "The chat was created, but couldn’t be cached. \(error.localizedDescription)" }
            return result.key
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    public func rename(_ session: SessionSummary, label: String) async {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let _: JSONValue = try await connection.request("sessions.patch",
                params: SessionsPatchParams(key: session.key, label: trimmed, expectedSessionId: session.sessionId), returning: JSONValue.self)
            revision += 1
            var updated = sessions.first(where: { $0.key == session.key }) ?? session
            updated.label = trimmed
            upsert(updated)
            try cache?.saveSessions([updated])
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    public func setModel(_ model: ModelSummary, for session: SessionSummary) async -> Bool {
        do {
            let _: JSONValue = try await connection.request("sessions.patch",
                params: SessionsPatchParams(key: session.key, model: model.selectionID, expectedSessionId: session.sessionId), returning: JSONValue.self)
            revision += 1
            var updated = sessions.first(where: { $0.key == session.key }) ?? session
            updated.model = model.selectionID
            upsert(updated)
            errorMessage = nil
            do { try cache?.saveSessions([updated]) }
            catch { errorMessage = "The model was chosen, but couldn’t be cached. \(error.localizedDescription)" }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    public func reset(_ session: SessionSummary) async {
        do {
            let _: JSONValue = try await connection.request("sessions.reset",
                params: SessionKeyParams(key: session.key, expectedSessionId: session.sessionId), returning: JSONValue.self)
            revision += 1
            try cache?.deleteHistory(session.key)
            await onInvalidatedSession?(session.key)
            await loadList()
        } catch { errorMessage = error.localizedDescription }
    }

    public func delete(_ session: SessionSummary) async {
        do {
            let _: JSONValue = try await connection.request("sessions.patch",
                params: SessionsPatchParams(key: session.key, archived: true, expectedSessionId: session.sessionId), returning: JSONValue.self)
            let _: JSONValue = try await connection.request("sessions.delete",
                params: SessionsDeleteParams(key: session.key, expectedSessionId: session.sessionId), returning: JSONValue.self)
            revision += 1
            sessions.removeAll { $0.key == session.key }
            searchResults?.removeAll { $0.key == session.key }
            try cache?.deleteSession(session.key)
            await onInvalidatedSession?(session.key)
        } catch { errorMessage = error.localizedDescription }
    }

    public func receive(_ change: SessionsChanged) async {
        revision += 1
        do {
            if change.reason == "delete", let key = change.sessionKey {
                // Ignore a delayed delete for a previous incarnation of the same key.
                if let removed = change.sessionId, let current = sessions.first(where: { $0.key == key })?.sessionId,
                   removed != current { return }
                sessions.removeAll { $0.key == key }
                searchResults?.removeAll { $0.key == key }
                try cache?.deleteSession(key)
                await onInvalidatedSession?(key)
            } else if let session = change.session {
                let previous = sessions.first(where: { $0.key == session.key })
                let replaced = previous?.sessionId != nil && session.sessionId != nil && previous?.sessionId != session.sessionId
                if replaced || change.reason == "reset" { try cache?.deleteHistory(session.key) }
                upsert(session)
                try cache?.saveSessions([session])
                if replaced || change.reason == "reset" { await onInvalidatedSession?(session.key) }
            } else {
                await loadList()
                if change.reason == "reset", let key = change.sessionKey {
                    try cache?.deleteHistory(key)
                    await onInvalidatedSession?(key)
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func upsert(_ session: SessionSummary) {
        if let index = searchResults?.firstIndex(where: { $0.key == session.key }) { searchResults?[index] = session }
        if let index = sessions.firstIndex(where: { $0.key == session.key }) { sessions[index] = session }
        else { sessions.append(session) }
        sortSessions()
    }

    private func sortSessions() {
        sessions.sort {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            let left = $0.lastActivityAt ?? $0.updatedAt ?? 0
            let right = $1.lastActivityAt ?? $1.updatedAt ?? 0
            return left == right ? $0.key < $1.key : left > right
        }
    }
}
