import SystemActions

public struct HomeRunningRow: Identifiable, Equatable, Sendable {
    public let sessionKey: String
    public let title: String
    public let status: RunActivityAttributes.Status
    public let needsApproval: Bool
    public var id: String { sessionKey }
    public var detail: String { status.label + (needsApproval ? " · Waiting on you" : "") }
}
