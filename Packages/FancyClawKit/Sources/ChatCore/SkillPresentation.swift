import Foundation
import GatewayProtocol

public enum SkillAvailability: Sendable {
    case ready, disabled, restricted, excludedFromAgent, missingRequirements, unavailable, unknown

    public var label: String {
        switch self {
        case .ready: "Ready"
        case .disabled: "Off"
        case .restricted: "Restricted"
        case .excludedFromAgent: "Not selected for agent"
        case .missingRequirements: "Missing requirements"
        case .unavailable: "Unavailable"
        case .unknown: "Status unavailable"
        }
    }
}

extension SkillStatus {
    public var availability: SkillAvailability {
        if disabled == true { return .disabled }
        if blockedByAllowlist == true { return .restricted }
        if blockedByAgentFilter == true { return .excludedFromAgent }
        if eligible == false {
            return missing?.isEmpty == false || platformIncompatible == true ? .missingRequirements : .unavailable
        }
        return eligible == true ? .ready : .unknown
    }

    public var displayGlyph: String {
        if let emoji, !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return emoji }
        return String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

/// Semantic accents mapped onto the current theme in the app, never raw brand colors in views.
public enum SkillAccent: Sendable {
    case coral, blue, green, violet, neutral
    public static func forSkill(_ skill: SkillStatus) -> Self {
        switch skill.skillKey.lowercased() {
        case "browser", "web-search", "weather": .blue
        case "spotify", "home-assistant": .green
        case "obsidian", "calendar": .violet
        case "gmail", "shell", "exec": .coral
        default: .neutral
        }
    }
}
