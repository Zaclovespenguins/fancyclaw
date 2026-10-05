import Foundation
import GatewayClient
import GatewayProtocol
import Observation

/// Read-only, same-connection skill metadata. No credentials, host paths or media are persisted.
@MainActor @Observable public final class SkillStore {
    public private(set) var skills: [SkillStatus] = []
    public private(set) var agentID: String?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var isStale = false
    public var search = ""
    public var errorMessage: String?
    private let connection: GatewayConnection
    private var loadTask: Task<Void, Never>?
    private var revision = 0

    public init(connection: GatewayConnection) { self.connection = connection }

    public var visibleSkills: [SkillStatus] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return skills.filter {
            query.isEmpty || $0.name.localizedStandardContains(query) || $0.description.localizedStandardContains(query)
                || $0.skillKey.localizedStandardContains(query)
        }
    }

    /// Coalesces tab-entry and lifecycle refreshes. Cancellation never publishes an error or a partial result.
    public func refresh() async {
        guard !Task.isCancelled else { return }
        if let loadTask { await loadTask.value; return }
        revision += 1
        let requestedRevision = revision
        isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.load(requestedRevision: requestedRevision)
        }
        loadTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func load(requestedRevision: Int) async {
        defer {
            if revision == requestedRevision { loadTask = nil; isLoading = false }
        }
        do {
            try Task.checkCancellation()
            let scopes = await connection.grantedScopes
            guard scopes.contains(where: { $0 == .read || $0 == .write || $0 == .admin }) else {
                throw GatewayErrorShape(code: .forbidden, message: "Your Gateway connection does not grant permission to access skills.")
            }
            let result = try await connection.request("skills.status", params: SkillsStatusParams(), returning: SkillsStatusResult.self)
            guard !Task.isCancelled, revision == requestedRevision else { return }
            skills = result.skills.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            agentID = result.agentId
            hasLoaded = true
            isStale = false
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, revision == requestedRevision else { return }
            isStale = hasLoaded
            errorMessage = error.localizedDescription
        }
    }

    /// Preserve a snapshot for offline reading, while rejecting replies from the abandoned socket.
    public func connectionDidDisconnect() {
        revision += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        isStale = hasLoaded
    }

    /// An explicit disconnect/profile replacement must not expose the previous Gateway's skills.
    public func clear() {
        connectionDidDisconnect()
        skills = []; agentID = nil; hasLoaded = false; isStale = false; errorMessage = nil; search = ""
    }
}
