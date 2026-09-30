/// Client ids the Gateway accepts in `connect.params.client.id` (`client-info.ts`). The schema enum is
/// closed, so unlike most protocol enums this one has no unknown case.
public enum GatewayClientID: String, Codable, Hashable, Sendable, CaseIterable {
    case webchatUI = "webchat-ui"
    case controlUI = "openclaw-control-ui"
    case browserCopilot = "openclaw-browser-copilot"
    case tui = "openclaw-tui"
    case webchat
    case cli
    case gatewayClient = "gateway-client"
    case macOSApp = "openclaw-macos"
    case linuxApp = "openclaw-linux"
    case iOSApp = "openclaw-ios"
    case watchOSApp = "openclaw-watchos"
    case androidApp = "openclaw-android"
    case nodeHost = "node-host"
    case worker = "openclaw-worker"
    case test
    case fingerprint
    case probe = "openclaw-probe"
}

/// Client modes the Gateway accepts in `connect.params.client.mode`. Closed, like ``GatewayClientID``.
public enum GatewayClientMode: String, Codable, Hashable, Sendable, CaseIterable {
    case webchat
    case cli
    case ui
    case backend
    case node
    case worker
    case probe
    case test
}

/// The role a connection authenticates as.
public enum GatewayRole: OpenEnum {
    case `operator`
    case node
    case worker
    case unknown(String)

    public static let knownCases: [GatewayRole] = [.operator, .node, .worker]

    public var rawValue: String {
        switch self {
        case .operator: "operator"
        case .node: "node"
        case .worker: "worker"
        case .unknown(let value): value
        }
    }
}

/// Operator authorization scopes (`src/gateway/operator-scopes.ts`).
public enum OperatorScope: OpenEnum {
    case read
    case write
    case admin
    case approvals
    case questions
    case pairing
    case talk
    case talkSecrets
    case unknown(String)

    public static let knownCases: [OperatorScope] = [
        .read, .write, .admin, .approvals, .questions, .pairing, .talk, .talkSecrets,
    ]

    public var rawValue: String {
        switch self {
        case .read: "operator.read"
        case .write: "operator.write"
        case .admin: "operator.admin"
        case .approvals: "operator.approvals"
        case .questions: "operator.questions"
        case .pairing: "operator.pairing"
        case .talk: "operator.talk"
        case .talkSecrets: "operator.talk.secrets"
        case .unknown(let value): value
        }
    }
}

/// Optional capabilities a client advertises in `connect.params.caps` (`GATEWAY_CLIENT_CAPS`).
///
/// Only the capabilities FancyClaw may advertise are named; the Gateway defines more.
public enum ClientCapability: OpenEnum {
    case toolEvents
    case approvals
    case execApprovals
    case pluginApprovals
    case sessionScopedEvents
    case unknown(String)

    public static let knownCases: [ClientCapability] = [
        .toolEvents, .approvals, .execApprovals, .pluginApprovals, .sessionScopedEvents,
    ]

    public var rawValue: String {
        switch self {
        case .toolEvents: "tool-events"
        case .approvals: "approvals"
        case .execApprovals: "exec-approvals"
        case .pluginApprovals: "plugin-approvals"
        case .sessionScopedEvents: "session-scoped-events"
        case .unknown(let value): value
        }
    }
}
