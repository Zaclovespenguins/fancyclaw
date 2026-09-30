import Foundation
import GatewayProtocol

/// Transient approval state; commands and decisions are never stored in the transcript cache.
public struct ConversationApproval: Identifiable, Hashable, Sendable {
    public var id: String { request.id }
    public let request: ExecApprovalRequest
    public var sessionKey: String?
    public var status: Status = .pending
    public var errorMessage: String?

    public enum Status: Hashable, Sendable {
        case pending
        case resolving
        case resolved(ApprovalDecision)
        case alreadyHandled
        case expired

        public var isPending: Bool { self == .pending || self == .resolving }
    }

    public init(request: ExecApprovalRequest, sessionKey: String?) {
        self.request = request
        self.sessionKey = sessionKey
    }
}
