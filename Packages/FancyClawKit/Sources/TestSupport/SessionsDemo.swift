import Foundation
import GatewayProtocol

/// A dedicated Chats fixture; Home's independently seeded roster stays unchanged.
public enum SessionsDemo {
    public static let pinnedKey = "agent:main:sessions-pinned"
    public static let runningKey = "agent:main:sessions-running"
    public static let yesterdayKey = "agent:main:sessions-yesterday"
    public static let earlierKey = "agent:main:sessions-earlier"
    public static let approvalID = "sessions-approval"

    public static func rows(now: Date = .now, calendar: Calendar = .current) -> [SessionSummary] {
        func milliseconds(daysAgo: Int) -> Double {
            (calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now).timeIntervalSince1970 * 1000
        }
        return [
            SessionSummary(key: pinnedKey, sessionId: "sessions-pinned", agentId: "main", label: "Gateway notes",
                lastMessagePreview: "Connection details and the commands we use to keep the Gateway healthy.",
                updatedAt: milliseconds(daysAgo: 14), pinned: true),
            SessionSummary(key: runningKey, sessionId: "sessions-running", agentId: "main", label: "Photo sync",
                lastMessagePreview: "Checking the date parser before publishing the fix. Your approval is needed to continue.",
                updatedAt: milliseconds(daysAgo: 0), hasActiveRun: true, activeRunIds: ["sessions-run"]),
            SessionSummary(key: yesterdayKey, sessionId: "sessions-yesterday", agentId: "main", label: "Weekend plans",
                lastMessagePreview: "A quiet morning hike, lunch by the lake, and a few ideas for Sunday.",
                updatedAt: milliseconds(daysAgo: 1)),
            SessionSummary(key: earlierKey, sessionId: "sessions-earlier", agentId: "main", label: "Packing checklist",
                lastMessagePreview: "Everything is ready for the trip: clothes, chargers, and the camera.",
                updatedAt: milliseconds(daysAgo: 5)),
            SessionSummary(key: "agent:main:sessions-archived", sessionId: "sessions-archived", agentId: "main",
                label: "Archived chat", updatedAt: milliseconds(daysAgo: 0), archived: true)
        ]
    }

    public static var history: [ChatMessage] {
        [ChatMessage(role: .assistant, content: [.text("The date parser is ready for review.")],
                     metadata: .init(id: "sessions-answer"))]
    }

    public static func approval(now: Date = .now) -> ExecApprovalRequest {
        let created = Int(now.timeIntervalSince1970 * 1000)
        return .init(id: approvalID, createdAtMs: created, expiresAtMs: created + 600_000,
            request: .init(command: "git push origin fix/date-parser", commandPreview: "Publish the date parser fix",
                allowedDecisions: [.allowOnce, .deny], sessionKey: runningKey))
    }
}
