import Foundation
import GatewayProtocol
import Testing
import TestSupport

@Suite("Event decoding")
struct EventDecodingTests {
    @Test func tick() throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "tick.event")
        #expect(frame.event == .tick(GatewayEvent.Tick(ts: 1_737_264_000_000)))
        #expect(frame.seq == 200)
    }

    @Test func shutdown() throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "shutdown.event")
        #expect(frame.event == .shutdown(GatewayEvent.Shutdown(reason: "restart", restartExpectedMs: 5000)))
    }

    @Test func approvalRequested() throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "exec-approval-requested.event")
        guard case .execApprovalRequested(let approval) = frame.event else { Issue.record("Expected approval"); return }
        #expect(approval.id == "approval-fake-0001")
        #expect(approval.request.command == "rm -rf ./build")
        #expect(approval.request.sessionKey == "agent:main:main")
        #expect(approval.offeredDecisions == [.allowOnce, .deny])
        #expect(approval.expiresAt == Date(timeIntervalSince1970: 1_737_264_120))
    }

    @Test func approvalResolved() throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "exec-approval-resolved.event")
        #expect(frame.event == .execApprovalResolved(ExecApprovalResolved(
            id: "approval-fake-0001", decision: .allowOnce, resolvedBy: "fancyclaw", ts: 1_737_264_005_000)))
    }

    @Test func denyIsAlwaysOffered() {
        let approval = ExecApprovalRequest(
            id: "a", createdAtMs: 0, expiresAtMs: 0,
            request: .init(command: "ls", allowedDecisions: [.allowOnce]))
        #expect(approval.offeredDecisions == [.allowOnce, .deny])
        let unrestricted = ExecApprovalRequest(id: "b", createdAtMs: 0, expiresAtMs: 0, request: .init(command: "ls"))
        #expect(unrestricted.offeredDecisions == [.allowOnce, .allowAlways, .deny])
    }

    @Test(arguments: ["agent-tool.event", "future.event", "no-payload.event"])
    func unmodeledEventsDecodeAsUnknown(fixture: String) throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: fixture)
        let raw = try Fixtures.frame(fixture)
        #expect(frame.event == .unknown(name: try #require(raw["event"]?.stringValue), payload: raw["payload"]))
    }

    @Test func stateVersionIsKept() throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "future.event")
        #expect(frame.stateVersion == StateVersion(presence: 3, health: 8))
    }

    @Test func malformedKnownEventThrows() {
        #expect(throws: DecodingError.self) {
            try decode(GatewayEventFrame.self, #"{"type":"event","event":"tick","payload":{"ts":"soon"}}"#)
        }
    }
}
