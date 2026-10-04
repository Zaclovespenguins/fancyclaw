import ChatCore
import Foundation
import GatewayProtocol
import SystemActions

public enum HomePresentation {
    public static func greeting(at date: Date, name: String, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? greeting : "\(greeting), \(trimmed)"
    }

    /// Home ignores a search left in Chats; the Gateway roster remains the source of recent rows.
    public static func recent(_ sessions: [SessionSummary]) -> [SessionSummary] {
        Array(sessions.filter { $0.archived != true }.prefix(5))
    }

    public static func running(sessions: [SessionSummary], runs: [RunActivityTracker.Run],
                               terminalIDs: Set<String>, approvals: [ConversationApproval]) -> [HomeRunningRow] {
        let archivedKeys = Set(sessions.filter { $0.archived == true }.map(\.key))
        let active = runs.filter { !$0.state.status.isTerminal && !terminalIDs.contains($0.attributes.runID)
            && !archivedKeys.contains($0.attributes.sessionKey) }
        let grouped = Dictionary(grouping: active, by: \.attributes.sessionKey)
        var keys = sessions.filter { session in
            guard session.archived != true else { return false }
            let ids = session.activeRunIds ?? []
            return ids.contains { !terminalIDs.contains($0) } || (session.hasActiveRun == true && ids.isEmpty)
        }.map(\.key)
        keys += grouped.keys.filter { !keys.contains($0) }.sorted()
        return keys.map { key in
            let session = sessions.first { $0.key == key }
            let run = grouped[key]?.sorted {
                let lhs = priority($0.state.status), rhs = priority($1.state.status)
                return lhs == rhs ? $0.attributes.runID < $1.attributes.runID : lhs > rhs
            }.first
            let needsApproval = approvals.contains { $0.sessionKey == key && $0.status.isPending }
            return HomeRunningRow(sessionKey: key, title: session?.title ?? run?.state.agentName ?? "New chat",
                                  status: run?.state.status ?? .thinking, needsApproval: needsApproval)
        }
    }

    private static func priority(_ status: RunActivityAttributes.Status) -> Int {
        switch status {
        case .streaming: 4
        case .finishing: 3
        case .reconnecting: 2
        default: 1
        }
    }
}
