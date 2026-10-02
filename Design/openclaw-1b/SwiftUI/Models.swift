import SwiftUI

struct Conversation: Identifiable, Hashable {
    enum Status { case idle, running, needsApproval }
    let id = UUID()
    var title: String
    var updatedLabel: String
    var status: Status = .idle
    var messages: [Message] = []
    static let empty = Conversation(title: "New chat", updatedLabel: "")
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Message: Identifiable {
    enum Content {
        case text(String)
        case toolSummary(icon: String, text: String)
        case steps([Step], elapsed: String)
        case diff(file: String, lines: [DiffLine])
        case approval(title: String, command: String)
        case link(title: String, meta: String, domain: String)
        case file(name: String, detail: String)
    }
    enum Role { case user, agent }
    let id = UUID()
    var role: Role
    var content: Content
}

struct Step: Identifiable {
    enum State { case done, active, pending }
    let id = UUID()
    var text: String
    var state: State
}

struct DiffLine: Identifiable {
    enum Kind { case context, add, remove }
    let id = UUID()
    var kind: Kind
    var text: String
}

struct AgentTask: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var progress: Double
}

struct Approval: Identifiable {
    let id = UUID()
    var title: String
    var command: String
}

struct Skill: Identifiable {
    let id = UUID()
    var name: String
    var glyph: String
    var color: Color
    var toolCount: Int
    var isEnabled: Bool
}

struct ActivityEvent: Identifiable {
    enum Kind { case needsYou, running, done }
    let id = UUID()
    var time: String
    var title: String
    var detail: String
    var kind: Kind
}

enum MockData {
    static let approvals = [Approval(title: "Push fix to photo-sync", command: "git push origin fix/date-parser")]

    static let running = [
        AgentTask(title: "photo-sync CI", detail: "Patching date parser", progress: 0.6),
        AgentTask(title: "Flight UA 914", detail: "On time · gate C12", progress: 0.35)
    ]

    static let conversations = [
        Conversation(title: "Weekend in Big Sur", updatedLabel: "4:52 PM", messages: bigSur),
        Conversation(title: "Inbox triage", updatedLabel: "Yesterday"),
        Conversation(title: "Quarterly invoices", updatedLabel: "Yesterday")
    ]

    static let bigSur: [Message] = [
        .init(role: .user, content: .text("Find a quiet place to stay in Big Sur this weekend, under $400 a night")),
        .init(role: .agent, content: .toolSummary(icon: "globe", text: "Browsed 14 listings on 3 sites")),
        .init(role: .agent, content: .text("Two options have Saturday and Sunday open. Both are off Highway 1 with no shared walls.")),
        .init(role: .agent, content: .link(title: "Deetjen's Big Sur Inn", meta: "$295 / night · Garden room", domain: "deetjens.com")),
        .init(role: .agent, content: .link(title: "Glen Oaks Cabins", meta: "$380 / night · Redwood cabin", domain: "glenoaksbigsur.com")),
        .init(role: .agent, content: .file(name: "bigsur-options.md", detail: "Saved to Obsidian · 2 KB"))
    ]

    static let skills = [
        Skill(name: "GitHub", glyph: "G", color: Color(hex: 0x4A4A55), toolCount: 14, isEnabled: true),
        Skill(name: "Shell", glyph: ">", color: Color(hex: 0x3A3A42), toolCount: 3, isEnabled: true),
        Skill(name: "Browser", glyph: "B", color: Color(hex: 0x4A86D9), toolCount: 9, isEnabled: true),
        Skill(name: "Calendar", glyph: "C", color: Color(hex: 0xE0473F), toolCount: 6, isEnabled: true),
        Skill(name: "Obsidian", glyph: "O", color: Color(hex: 0x8A55D6), toolCount: 5, isEnabled: true),
        Skill(name: "Gmail", glyph: "M", color: Color(hex: 0xDB5A3A), toolCount: 8, isEnabled: false),
        Skill(name: "Home Assistant", glyph: "H", color: Color(hex: 0x3B9AC4), toolCount: 12, isEnabled: false),
        Skill(name: "Spotify", glyph: "S", color: Color(hex: 0x3DBA6E), toolCount: 7, isEnabled: false)
    ]

    static let activity = [
        ActivityEvent(time: "9:41", title: "Approve git push", detail: "photo-sync is waiting on you", kind: .needsYou),
        ActivityEvent(time: "9:36", title: "Patching date parser", detail: "2 files changed, re-running tests", kind: .running),
        ActivityEvent(time: "6:10", title: "Watching UA 914", detail: "Checks every 15 min", kind: .running),
        ActivityEvent(time: "4:52", title: "Saved Big Sur options", detail: "bigsur-options.md in Obsidian", kind: .done),
        ActivityEvent(time: "2:15", title: "Drafted 6 invoices", detail: "Stripe · ready to send", kind: .done),
        ActivityEvent(time: "7:00", title: "Morning briefing", detail: "Sent to Telegram", kind: .done)
    ]
}
