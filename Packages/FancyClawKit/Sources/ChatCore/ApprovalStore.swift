import Foundation
import GatewayClient
import GatewayProtocol
import Observation

/// One store per Gateway connection, so approvals in unvisited chats still produce badges.
@MainActor @Observable
public final class ApprovalStore {
    public private(set) var approvals: [ConversationApproval] = []
    public private(set) var currentDate: Date
    public private(set) var hasApprovalScope = false
    public var permissionMessage: String? {
        hasApprovalScope ? nil : "This connection can’t decide commands. Ask the Gateway owner to grant operator.approvals, then reconnect."
    }

    @ObservationIgnored private let connection: GatewayConnection?
    @ObservationIgnored private let resolveRequest: @Sendable (ExecApprovalResolveParams) async throws -> Void
    @ObservationIgnored private let timing: GatewayTiming
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var resolved: [String: ApprovalDecision] = [:]
    @ObservationIgnored private var runSessions: [String: String] = [:]
    @ObservationIgnored private var generation = UUID()

    public init(connection: GatewayConnection, timing: GatewayTiming = .continuous,
                now: @escaping @Sendable () -> Date = { .now }) {
        self.connection = connection
        self.timing = timing
        self.now = now
        currentDate = now()
        resolveRequest = { params in
            let response = try await connection.request("exec.approval.resolve", params: params, returning: JSONValue.self)
            guard response["ok"]?.boolValue == true else { throw ConnectionError.invalidResponse }
        }
    }

    /// An injected RPC operation keeps reducer/race tests independent of socket timing.
    public init(scopes: [OperatorScope], timing: GatewayTiming = .continuous,
                now: @escaping @Sendable () -> Date = { .now },
                resolve: @escaping @Sendable (ExecApprovalResolveParams) async throws -> Void) {
        connection = nil
        self.timing = timing
        self.now = now
        currentDate = now()
        resolveRequest = resolve
        updateScopes(scopes)
    }

    public func updateScopes(_ scopes: [OperatorScope]) {
        let previousPermission = permissionMessage
        hasApprovalScope = scopes.contains(.approvals) || scopes.contains(.admin)
        if hasApprovalScope, let previousPermission {
            for index in approvals.indices where approvals[index].errorMessage == previousPermission {
                approvals[index].errorMessage = nil
            }
        }
    }

    public func start() async {
        guard eventTask == nil, !isStarting, let connection else { return }
        isStarting = true
        let token = generation
        defer { if generation == token { isStarting = false } }
        let events = await connection.events()
        let scopes = await connection.grantedScopes
        guard generation == token, eventTask == nil else { return }
        updateScopes(scopes)
        eventTask = Task { [weak self] in
            for await frame in events {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.receive(frame)
            }
        }
        startExpiryUpdates()
        refreshExpiry()
    }

    public func stop() {
        generation = UUID()
        eventTask?.cancel()
        eventTask = nil
        isStarting = false
        expiryTask?.cancel()
        expiryTask = nil
        for index in approvals.indices where approvals[index].status == .resolving {
            approvals[index].status = .pending
        }
        refreshExpiry()
    }

    public func approvals(for sessionKey: String) -> [ConversationApproval] {
        // Requests with no session/run association remain visible with an explicit label in every chat.
        approvals.filter { $0.sessionKey == sessionKey || $0.sessionKey == nil }
    }

    public func pendingCount(for sessionKey: String? = nil) -> Int {
        approvals.count { $0.status.isPending && (sessionKey == nil || $0.sessionKey == sessionKey) }
    }

    public func receive(_ frame: GatewayEventFrame) {
        refreshExpiry()
        switch frame.event {
        case .execApprovalRequested(let request):
            guard !approvals.contains(where: { $0.id == request.id }) else { return }
            var approval = ConversationApproval(request: request,
                sessionKey: request.request.sessionKey ?? request.request.runId.flatMap { runSessions[$0] })
            if let decision = resolved[request.id] { approval.status = .resolved(decision) }
            else if request.expiresAt <= currentDate { approval.status = .expired }
            approvals.append(approval)
            startExpiryUpdates()
        case .execApprovalResolved(let event):
            resolved[event.id] = resolved[event.id] ?? event.decision
            if let index = approvals.firstIndex(where: { $0.id == event.id }) {
                approvals[index].status = .resolved(resolved[event.id] ?? event.decision)
                approvals[index].errorMessage = nil
            }
        case .chat(let event): associate(runID: event.runId, sessionKey: event.sessionKey)
        case .agent(let event):
            if let key = event.sessionKey { associate(runID: event.runId, sessionKey: key) }
        default: break
        }
    }

    private func associate(runID: String, sessionKey: String) {
        runSessions[runID] = sessionKey
        for index in approvals.indices where approvals[index].sessionKey == nil && approvals[index].request.request.runId == runID {
            approvals[index].sessionKey = sessionKey
        }
    }

    public func refreshExpiry() {
        currentDate = now()
        for index in approvals.indices where approvals[index].status == .pending && approvals[index].request.expiresAt <= currentDate {
            approvals[index].status = .expired
            approvals[index].errorMessage = nil
        }
    }

    public func resolve(id: String, decision: ApprovalDecision) async {
        refreshExpiry()
        guard hasApprovalScope, let index = approvals.firstIndex(where: { $0.id == id }),
              approvals[index].status == .pending, approvals[index].request.offeredDecisions.contains(decision) else { return }
        let token = generation
        approvals[index].status = .resolving
        approvals[index].errorMessage = nil
        do {
            try await resolveRequest(.init(id: id, decision: decision))
            guard generation == token, approvals[index].status == .resolving else { return }
            resolved[id] = decision
            approvals[index].status = .resolved(decision)
        } catch {
            // A resolved event wins over a late RPC response or error.
            guard generation == token, approvals[index].status == .resolving else { return }
            if let error = error as? GatewayErrorShape, error.code == .approvalNotFound {
                approvals[index].status = .alreadyHandled
            } else {
                approvals[index].status = .pending
                if let error = error as? GatewayErrorShape, error.detailCode == .missingScope {
                    hasApprovalScope = false
                    approvals[index].errorMessage = permissionMessage
                } else {
                    approvals[index].errorMessage = "Couldn’t send the decision. \(error.localizedDescription)"
                }
                refreshExpiry()
            }
        }
    }

    private func startExpiryUpdates() {
        guard expiryTask == nil else { return }
        expiryTask = Task { [weak self, timing] in
            while !Task.isCancelled {
                do { try await timing.sleep(.seconds(1)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.refreshExpiry()
                if !self.approvals.contains(where: { $0.status.isPending }) {
                    self.expiryTask = nil
                    return
                }
            }
        }
    }
}
