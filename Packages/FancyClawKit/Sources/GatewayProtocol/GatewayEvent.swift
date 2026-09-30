/// An event frame whose payload is decoded according to its event name.
public struct GatewayEventFrame: Hashable, Sendable {
    public var event: GatewayEvent
    /// The broadcast sequence number; a gap means events were missed and state should be resynced.
    public var seq: Int?
    public var stateVersion: StateVersion?

    public init(event: GatewayEvent, seq: Int? = nil, stateVersion: StateVersion? = nil) {
        self.event = event
        self.seq = seq
        self.stateVersion = stateVersion
    }
}

/// The Gateway events FancyClaw understands. Anything else decodes as ``unknown(name:payload:)``.
public enum GatewayEvent: Hashable, Sendable {
    case connectChallenge(ConnectChallenge)
    case chat(ChatEvent)
    case agent(AgentEvent)
    case sessionsChanged(SessionsChanged)
    case tick(Tick)
    case shutdown(Shutdown)
    case execApprovalRequested(ExecApprovalRequest)
    case execApprovalResolved(ExecApprovalResolved)
    case unknown(name: String, payload: JSONValue?)

    public var name: String {
        switch self {
        case .connectChallenge: Name.connectChallenge
        case .chat: Name.chat
        case .agent: "agent"
        case .sessionsChanged: "sessions.changed"
        case .tick: Name.tick
        case .shutdown: Name.shutdown
        case .execApprovalRequested: Name.execApprovalRequested
        case .execApprovalResolved: Name.execApprovalResolved
        case .unknown(let name, _): name
        }
    }

    public enum Name {
        public static let connectChallenge = "connect.challenge"
        public static let chat = "chat"
        public static let tick = "tick"
        public static let shutdown = "shutdown"
        public static let execApprovalRequested = "exec.approval.requested"
        public static let execApprovalResolved = "exec.approval.resolved"
    }

    /// The periodic keepalive, sent every `policy.tickIntervalMs`.
    public struct Tick: Codable, Hashable, Sendable {
        public var ts: Int

        public init(ts: Int) {
            self.ts = ts
        }
    }

    /// The Gateway is going away; reconnect after `restartExpectedMs` if given.
    public struct Shutdown: Codable, Hashable, Sendable {
        public var reason: String
        public var restartExpectedMs: Int?

        public init(reason: String, restartExpectedMs: Int? = nil) {
            self.reason = reason
            self.restartExpectedMs = restartExpectedMs
        }
    }
}

extension GatewayEventFrame: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, event, payload, seq, stateVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.expectFrameType(.event)
        seq = try container.decodeIfPresent(Int.self, forKey: .seq)
        stateVersion = try container.decodeIfPresent(StateVersion.self, forKey: .stateVersion)

        func payload<T: Decodable>(_: T.Type) throws -> T {
            try container.decode(T.self, forKey: .payload)
        }
        switch try container.decode(String.self, forKey: .event) {
        case GatewayEvent.Name.connectChallenge: event = .connectChallenge(try payload(ConnectChallenge.self))
        case GatewayEvent.Name.chat: event = .chat(try payload(ChatEvent.self))
        case "agent": event = .agent(try payload(AgentEvent.self))
        case "sessions.changed": event = .sessionsChanged(try payload(SessionsChanged.self))
        case GatewayEvent.Name.tick: event = .tick(try payload(GatewayEvent.Tick.self))
        case GatewayEvent.Name.shutdown: event = .shutdown(try payload(GatewayEvent.Shutdown.self))
        case GatewayEvent.Name.execApprovalRequested: event = .execApprovalRequested(try payload(ExecApprovalRequest.self))
        case GatewayEvent.Name.execApprovalResolved: event = .execApprovalResolved(try payload(ExecApprovalResolved.self))
        case let name: event = .unknown(name: name, payload: try container.decodeIfPresent(JSONValue.self, forKey: .payload))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(FrameType.event, forKey: .type)
        try container.encode(event.name, forKey: .event)
        switch event {
        case .connectChallenge(let payload): try container.encode(payload, forKey: .payload)
        case .chat(let payload): try container.encode(payload, forKey: .payload)
        case .agent(let payload): try container.encode(payload, forKey: .payload)
        case .sessionsChanged(let payload): try container.encode(payload, forKey: .payload)
        case .tick(let payload): try container.encode(payload, forKey: .payload)
        case .shutdown(let payload): try container.encode(payload, forKey: .payload)
        case .execApprovalRequested(let payload): try container.encode(payload, forKey: .payload)
        case .execApprovalResolved(let payload): try container.encode(payload, forKey: .payload)
        case .unknown(_, let payload): try container.encodeIfPresent(payload, forKey: .payload)
        }
        try container.encodeIfPresent(seq, forKey: .seq)
        try container.encodeIfPresent(stateVersion, forKey: .stateVersion)
    }
}
