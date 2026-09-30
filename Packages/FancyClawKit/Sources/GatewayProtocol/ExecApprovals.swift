import Foundation

/// The `exec.approval.requested` event payload: an agent wants to run a command and needs a decision.
public struct ExecApprovalRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAtMs: Int
    public var expiresAtMs: Int
    public var request: Details

    public init(id: String, createdAtMs: Int, expiresAtMs: Int, request: Details) {
        self.id = id
        self.createdAtMs = createdAtMs
        self.expiresAtMs = expiresAtMs
        self.request = request
    }

    public var expiresAt: Date { Date(gatewayMilliseconds: expiresAtMs) }

    /// The decisions to offer: those in `allowedDecisions`, or all of them if the Gateway didn't say.
    /// Deny is always offered.
    public var offeredDecisions: [ApprovalDecision] {
        let unavailable = request.unavailableDecisions ?? []
        var decisions = (request.allowedDecisions ?? [.allowOnce, .allowAlways, .deny])
            .filter { $0.isKnown && !unavailable.contains($0) }
        decisions = ApprovalDecision.knownCases.filter { decisions.contains($0) }
        if !decisions.contains(.deny) { decisions.append(.deny) }
        return decisions
    }

    public struct Details: Codable, Hashable, Sendable {
        public var command: String
        public var commandPreview: String?
        public var cwd: String?
        public var host: String?
        public var warningText: String?
        public var allowedDecisions: [ApprovalDecision]?
        public var unavailableDecisions: [ApprovalDecision]?
        public var agentId: String?
        public var sessionKey: String?
        public var runId: String?
        public var toolCallId: String?

        public init(
            command: String, commandPreview: String? = nil, cwd: String? = nil, host: String? = nil,
            warningText: String? = nil, allowedDecisions: [ApprovalDecision]? = nil,
            unavailableDecisions: [ApprovalDecision]? = nil, agentId: String? = nil, sessionKey: String? = nil,
            runId: String? = nil, toolCallId: String? = nil
        ) {
            self.command = command
            self.commandPreview = commandPreview
            self.cwd = cwd
            self.host = host
            self.warningText = warningText
            self.allowedDecisions = allowedDecisions
            self.unavailableDecisions = unavailableDecisions
            self.agentId = agentId
            self.sessionKey = sessionKey
            self.runId = runId
            self.toolCallId = toolCallId
        }
    }
}

/// The `exec.approval.resolved` event payload, sent however the approval was decided.
public struct ExecApprovalResolved: Codable, Hashable, Sendable {
    public var id: String
    public var decision: ApprovalDecision
    public var resolvedBy: String?
    public var ts: Int?

    public init(id: String, decision: ApprovalDecision, resolvedBy: String? = nil, ts: Int? = nil) {
        self.id = id
        self.decision = decision
        self.resolvedBy = resolvedBy
        self.ts = ts
    }
}

/// Parameters of `exec.approval.resolve`. An unknown or expired id fails with `APPROVAL_NOT_FOUND`.
public struct ExecApprovalResolveParams: Codable, Hashable, Sendable {
    public var id: String
    public var decision: ApprovalDecision

    public init(id: String, decision: ApprovalDecision) {
        self.id = id
        self.decision = decision
    }

    private enum CodingKeys: String, CodingKey { case id, decision }

    public func encode(to encoder: any Encoder) throws {
        guard decision.isKnown else {
            throw EncodingError.invalidValue(decision, .init(codingPath: encoder.codingPath,
                debugDescription: "Cannot send an unknown approval decision."))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(decision, forKey: .decision)
    }
}

public enum ApprovalDecision: OpenEnum {
    case allowOnce
    case allowAlways
    case deny
    case unknown(String)

    public static let knownCases: [ApprovalDecision] = [.allowOnce, .allowAlways, .deny]

    public var rawValue: String {
        switch self {
        case .allowOnce: "allow-once"
        case .allowAlways: "allow-always"
        case .deny: "deny"
        case .unknown(let value): value
        }
    }
}
