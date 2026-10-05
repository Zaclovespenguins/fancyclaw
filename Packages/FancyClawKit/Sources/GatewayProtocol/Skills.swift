/// The pinned `skills.status` request schema is closed; omit absent context fields.
public struct SkillsStatusParams: Codable, Sendable {
    public let agentId: String?
    public let sessionKey: String?
    public init(agentId: String? = nil, sessionKey: String? = nil) {
        self.agentId = agentId; self.sessionKey = sessionKey
    }
}

/// Source-derived from OpenClaw 2026.9.6 `src/skills/discovery/status.ts`.
/// The published protocol schema defines request params but no result shape for this RPC.
public struct SkillsStatusResult: Codable, Sendable {
    public var agentId: String?
    public var agentSkillFilter: [String]?
    public var skills: [SkillStatus]
    public init(agentId: String? = nil, agentSkillFilter: [String]? = nil, skills: [SkillStatus]) {
        self.agentId = agentId; self.agentSkillFilter = agentSkillFilter; self.skills = skills
    }
}

public struct SkillStatus: Codable, Sendable, Identifiable {
    public var name: String
    public var description: String
    public var skillKey: String
    /// An open string supplied by the Gateway; unfamiliar source labels remain intact.
    public var source: String?
    public var emoji: String?
    public var disabled: Bool?
    public var eligible: Bool?
    public var blockedByAllowlist: Bool?
    public var blockedByAgentFilter: Bool?
    public var platformIncompatible: Bool?
    public var modelVisible: Bool?
    public var userInvocable: Bool?
    public var commandVisible: Bool?
    public var requirements: SkillRequirements?
    public var missing: SkillRequirements?

    /// Discovery deduplicates by name; a metadata-provided config key can be shared by different skills.
    public var id: String { name }

    public init(name: String, description: String, skillKey: String, source: String? = nil, emoji: String? = nil,
                disabled: Bool? = nil, eligible: Bool? = nil, blockedByAllowlist: Bool? = nil,
                blockedByAgentFilter: Bool? = nil, platformIncompatible: Bool? = nil,
                modelVisible: Bool? = nil, userInvocable: Bool? = nil, commandVisible: Bool? = nil,
                requirements: SkillRequirements? = nil, missing: SkillRequirements? = nil) {
        self.name = name; self.description = description; self.skillKey = skillKey; self.source = source
        self.emoji = emoji; self.disabled = disabled; self.eligible = eligible
        self.blockedByAllowlist = blockedByAllowlist; self.blockedByAgentFilter = blockedByAgentFilter
        self.platformIncompatible = platformIncompatible; self.modelVisible = modelVisible
        self.userInvocable = userInvocable; self.commandVisible = commandVisible
        self.requirements = requirements; self.missing = missing
    }
}

/// `anyBins` is a set of alternatives: one binary suffices, unlike the all-required `bins` list.
public struct SkillRequirements: Codable, Sendable {
    public var bins: [String]?
    public var anyBins: [String]?
    public var env: [String]?
    public var config: [String]?
    public var os: [String]?
    public init(bins: [String]? = nil, anyBins: [String]? = nil, env: [String]? = nil,
                config: [String]? = nil, os: [String]? = nil) {
        self.bins = bins; self.anyBins = anyBins; self.env = env; self.config = config; self.os = os
    }
    public var isEmpty: Bool {
        [bins, anyBins, env, config, os].allSatisfy { $0?.isEmpty != false }
    }
}
