import ChatCore
import Foundation
import GatewayProtocol
import TestSupport
import Testing

@Suite("Chats list presentation")
struct SessionListPresentationTests {
    @Test func groupsUseActivityDatePinnedPrecedenceAndPreserveRosterOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let earlier = try #require(calendar.date(byAdding: .day, value: -4, to: now))
        let rows = [
            SessionSummary(key: "today-1", updatedAt: now.timeIntervalSince1970 * 1000),
            SessionSummary(key: "pinned", updatedAt: earlier.timeIntervalSince1970 * 1000, pinned: true),
            SessionSummary(key: "yesterday", updatedAt: now.timeIntervalSince1970 * 1000,
                lastActivityAt: yesterday.timeIntervalSince1970 * 1000),
            SessionSummary(key: "today-2", updatedAt: now.timeIntervalSince1970 * 1000),
            SessionSummary(key: "earlier", updatedAt: earlier.timeIntervalSince1970 * 1000),
            SessionSummary(key: "undated")
        ]
        let groups = SessionListPresentation.groups(rows, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Pinned", "Today", "Yesterday", "Earlier"])
        #expect(groups.map { $0.rows.map(\.key) } == [["pinned"], ["today-1", "today-2"], ["yesterday"], ["earlier", "undated"]])
        #expect(SessionListPresentation.activityDate(for: rows[2]) == yesterday)
        #expect(SessionListPresentation.activityDate(for: rows[5]) == nil)
        #expect(SessionListPresentation.groups([], now: now, calendar: calendar).isEmpty)
    }

    @Test func yesterdayIsCalendarDayAcrossDaylightSavingBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        // 2026 spring-forward day is 23 hours long: yesterday cannot be found by subtracting 24 hours.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 30)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0, minute: 15)))
        let row = SessionSummary(key: "s", lastActivityAt: yesterday.timeIntervalSince1970 * 1000)
        #expect(SessionListPresentation.groups([row], now: now, calendar: calendar).map(\.title) == ["Yesterday"])
    }

    @Test func sessionsDemoExercisesAllGroupsAndCombinedStatus() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12)))
        let rows = SessionsDemo.rows(now: now, calendar: calendar).filter { $0.archived != true }
        let groups = SessionListPresentation.groups(rows, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Pinned", "Today", "Yesterday", "Earlier"])
        #expect(groups.allSatisfy { $0.rows.count == 1 })
        let running = try #require(rows.first { $0.key == SessionsDemo.runningKey })
        #expect(running.hasActiveRun == true)
        #expect(SessionsDemo.approval(now: now).request.sessionKey == running.key)
        #expect(rows.allSatisfy { !($0.lastMessagePreview ?? "").isEmpty })
    }
}
