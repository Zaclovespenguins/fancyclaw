import Foundation
import GatewayProtocol

/// Presentation-only grouping. The roster/search store remains responsible for filtering and ordering.
public enum SessionListPresentation {
    public static func activityDate(for session: SessionSummary) -> Date? {
        (session.lastActivityAt ?? session.updatedAt).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    public static func groups(
        _ sessions: [SessionSummary], now: Date = .now, calendar: Calendar = .current
    ) -> [(title: String, rows: [SessionSummary])] {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        func groupIndex(for session: SessionSummary) -> Int {
            if session.pinned == true { return 0 }
            guard let date = activityDate(for: session) else { return 3 }
            if calendar.isDate(date, inSameDayAs: now) { return 1 }
            if let yesterday, calendar.isDate(date, inSameDayAs: yesterday) { return 2 }
            return 3
        }
        return ["Pinned", "Today", "Yesterday", "Earlier"].enumerated().compactMap { index, title in
            let matching = sessions.filter { groupIndex(for: $0) == index }
            return matching.isEmpty ? nil : (title, matching)
        }
    }
}
