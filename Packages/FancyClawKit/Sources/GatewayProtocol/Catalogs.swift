public struct AgentSummary: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String?
    public init(id: String, name: String? = nil) { self.id = id; self.name = name }
}

public struct AgentsListResult: Codable, Sendable {
    public var defaultId: String?
    public var mainKey: String?
    public var agents: [AgentSummary]
}

public struct ModelSummary: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var provider: String
    public var available: Bool?
    public init(id: String, name: String, provider: String, available: Bool? = nil) {
        self.id = id; self.name = name; self.provider = provider; self.available = available
    }
    public var selectionID: String { "\(provider)/\(id)" }
}

public struct ModelsListParams: Codable, Sendable {
    public let view: String
    public init() { view = "configured" }
}

public struct ModelsListResult: Codable, Sendable {
    public var models: [ModelSummary]
}
