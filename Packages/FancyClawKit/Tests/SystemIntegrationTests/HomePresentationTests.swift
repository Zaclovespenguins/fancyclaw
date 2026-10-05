import ChatCore
import Foundation
import GatewayProtocol
import SystemActions
@testable import SystemIntegration
import Testing

@Suite("Home presentation") struct HomePresentationTests {
    @Test(arguments: [(0, "Good morning"), (11, "Good morning"), (12, "Good afternoon"), (17, "Good afternoon"), (18, "Good evening"), (23, "Good evening")])
    func greetingUsesLocalTimeAndTrimsName(_ example: (Int, String)) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: example.0)))
        #expect(HomePresentation.greeting(at: date, name: " \n", calendar: calendar) == example.1)
        #expect(HomePresentation.greeting(at: date, name: " Sam \n", calendar: calendar) == example.1 + ", Sam")
    }

    @Test func runningMergeDeduplicatesSuppressesTerminalAndIncludesActivityOnlySessions() {
        func run(_ id: String, _ key: String, _ status: RunActivityAttributes.Status) -> RunActivityTracker.Run {
            .init(attributes: .init(runID: id, sessionKey: key), state: .init(agentName: "Helper", startedAt: .distantPast, status: status))
        }
        let sessions = [SessionSummary(key: "a", label: "Photos", hasActiveRun: true, activeRunIds: ["r1", "r2"]),
                        SessionSummary(key: "ended", hasActiveRun: true, activeRunIds: ["done"]),
                        SessionSummary(key: "fallback", label: "Notes", hasActiveRun: true),
                        SessionSummary(key: "archived", archived: true, hasActiveRun: true)]
        let approval = ConversationApproval(request: .init(id: "approval", createdAtMs: 0, expiresAtMs: 999999,
            request: .init(command: "pwd", sessionKey: "a")), sessionKey: "a")
        let rows = HomePresentation.running(sessions: sessions,
            runs: [run("r1", "a", .thinking), run("r2", "a", .streaming), run("r3", "unknown", .finishing), run("done", "ended", .completed), run("r4", "archived", .streaming)],
            terminalIDs: ["done"], approvals: [approval])
        #expect(rows.map(\.sessionKey) == ["a", "fallback", "unknown"])
        #expect(rows[0].title == "Photos" && rows[0].detail == "Replying · Waiting on you")
        #expect(rows[1].status == .thinking)
        #expect(rows[2].title == "Helper" && rows[2].status == .finishing)
    }

    @Test func recentUsesFirstFiveUnarchivedRosterRows() {
        let rows = (0..<7).map { SessionSummary(key: "\($0)", archived: $0 == 1) }
        #expect(HomePresentation.recent(rows).map(\.key) == ["0", "2", "3", "4", "5"])
    }
}
