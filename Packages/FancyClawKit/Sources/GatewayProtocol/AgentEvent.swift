/// Agent streams stay open to future data shapes. Chat text is rendered from chat events only.
public struct AgentEvent: Codable, Hashable, Sendable {
    public var runId: String
    public var seq: Int
    public var stream: String
    public var ts: Double
    public var sessionKey: String?
    public var agentId: String?
    public var data: JSONValue

    public init(runId: String, seq: Int, stream: String, ts: Double = 0,
                sessionKey: String? = nil, agentId: String? = nil, data: JSONValue) {
        self.runId = runId
        self.seq = seq
        self.stream = stream
        self.ts = ts
        self.sessionKey = sessionKey
        self.agentId = agentId
        self.data = data
    }
}
