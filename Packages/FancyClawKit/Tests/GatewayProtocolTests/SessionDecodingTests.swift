import Foundation
import GatewayProtocol
import Testing
import TestSupport

@Suite("Session decoding")
struct SessionDecodingTests {
    @Test func messageChangeHasPhaseWithoutReason() throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "sessions-changed-message.event")
        guard case .sessionsChanged(let change) = frame.event else {
            Issue.record("Expected session change"); return
        }
        #expect(change.sessionKey == "agent:main:main")
        #expect(change.reason == nil)
        #expect(change.phase == "message")
        #expect(change.ts == 1_737_264_003_000)
        #expect(frame.seq == 104)
    }

    @Test func lifecycleChangeKeepsReasonAndSnapshot() throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "sessions-changed-lifecycle.event")
        guard case .sessionsChanged(let change) = frame.event else {
            Issue.record("Expected session change"); return
        }
        #expect(change.reason == "update")
        #expect(change.phase == nil)
        #expect(change.session?.label == "Updated chat")
    }

    @Test func futurePhaseAndMissingDiscriminatorsDecode() throws {
        let future = try decode(SessionsChanged.self, #"{"phase":"future","reason":"future","extra":true}"#)
        #expect(future.phase == "future")
        #expect(future.reason == "future")
        let missing = try decode(SessionsChanged.self, #"{"sessionKey":"s"}"#)
        #expect(missing.phase == nil)
        #expect(missing.reason == nil)
    }

    @Test func list() throws {
        let result = try #require(Fixtures.decode(ResponseFrame<SessionsListResult>.self, from: "sessions-list.res").payload)
        #expect(result.sessions.map(\.key) == ["agent:main:main", "agent:main:fake-0002"])
        #expect(result.totalCount == 2)

        let first = result.sessions[0]
        #expect(first.kind == .direct)
        #expect(first.status == .done)
        #expect(first.pinned == true)
        #expect(first.updatedDate == Date(timeIntervalSince1970: 1_737_264_003))

        let second = result.sessions[1]
        #expect(second.updatedAt == nil)
        #expect(second.hasActiveRun == true)
        #expect(second.activeRunIds == ["run-fake-0002"])
    }

    @Test func unknownKindAndStatusDecode() throws {
        let row = try decode(SessionSummary.self, #"{"key":"k","kind":"brand-new-kind","status":"sleeping"}"#)
        #expect(row.kind == .unknown("brand-new-kind"))
        #expect(row.status == .unknown("sleeping"))
        #expect(try decode(SessionSummary.self, #"{"key":"k","kind":"unknown"}"#).kind == .unclassified)
    }

    @Test(arguments: [
        (SessionSummary(key: "k", label: "Label", displayName: "Display", derivedTitle: "Derived"), "Label" as String?),
        (SessionSummary(key: "k", displayName: "Display", derivedTitle: "Derived"), "Display"),
        (SessionSummary(key: "k", label: "  ", derivedTitle: "Derived"), "Derived"),
        (SessionSummary(key: "k"), nil),
    ])
    func titlePrecedence(session: SessionSummary, expected: String?) {
        #expect(session.title == expected)
    }
}
