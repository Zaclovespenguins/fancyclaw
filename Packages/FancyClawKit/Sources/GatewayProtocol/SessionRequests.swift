import Foundation

public struct SessionsCreateParams: Codable, Sendable {
    public var agentId: String?
    public var idempotencyKey: String
    public init(agentId: String? = nil, idempotencyKey: String = UUID().uuidString) {
        self.agentId = agentId
        self.idempotencyKey = idempotencyKey
    }
}

public struct SessionsCreateResult: Codable, Sendable {
    public var key: String
    public var sessionId: String?
}

public struct SessionsPatchParams: Codable, Sendable {
    public var key: String
    public var label: String?
    public var model: String?
    public var archived: Bool?
    public var expectedSessionId: String?
    public init(key: String, label: String? = nil, model: String? = nil,
                archived: Bool? = nil, expectedSessionId: String? = nil) {
        self.key = key
        self.label = label
        self.model = model
        self.archived = archived
        self.expectedSessionId = expectedSessionId
    }
}

public struct SessionKeyParams: Codable, Sendable {
    public var key: String
    public var expectedSessionId: String?
    public init(key: String, expectedSessionId: String? = nil) {
        self.key = key
        self.expectedSessionId = expectedSessionId
    }
}

public struct SessionsDeleteParams: Codable, Sendable {
    public var key: String
    public var expectedSessionId: String?
    public let archivedOnly = true
    public let deleteTranscript = true
    public init(key: String, expectedSessionId: String? = nil) {
        self.key = key
        self.expectedSessionId = expectedSessionId
    }
    private enum CodingKeys: String, CodingKey { case key, expectedSessionId, archivedOnly, deleteTranscript }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        expectedSessionId = try values.decodeIfPresent(String.self, forKey: .expectedSessionId)
    }
}

public struct SessionsChanged: Codable, Hashable, Sendable {
    public var sessionKey: String?
    /// Lifecycle changes carry a reason; transcript notifications may carry only a phase.
    public var reason: String?
    public var phase: String?
    public var ts: Double?
    public var session: SessionSummary?
    public var sessionId: String?
    public init(sessionKey: String? = nil, reason: String? = nil, ts: Double? = nil,
                session: SessionSummary? = nil, sessionId: String? = nil, phase: String? = nil) {
        self.sessionKey = sessionKey
        self.reason = reason
        self.phase = phase
        self.ts = ts
        self.session = session
        self.sessionId = sessionId
    }
}
