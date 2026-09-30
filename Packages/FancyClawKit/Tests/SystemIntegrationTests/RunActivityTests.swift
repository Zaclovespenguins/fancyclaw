import Foundation
import GatewayClient
import GatewayProtocol
import SystemIntegration
import SystemActions
import Testing

struct RunActivityTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func chat(_ state: ChatEvent.State, seq: Int = 1, run: String = "run", key: String = "agent:main:main") -> GatewayEventFrame {
        .init(event: .chat(.init(runId: run, sessionKey: key, seq: seq, state: state)))
    }

    private func lifecycle(_ phase: String, seq: Int, key: String? = "agent:main:main") -> GatewayEventFrame {
        .init(event: .agent(.init(runId: "run", seq: seq, stream: "lifecycle", sessionKey: key, agentId: "main",
            data: ["phase": .string(phase), "startedAt": 990_000])))
    }

    @Test func attributesAndStatesRoundTripWithoutTranscriptContent() throws {
        let attributes = RunActivityAttributes(runID: "run", sessionKey: "agent:main:main")
        #expect(try JSONDecoder().decode(RunActivityAttributes.self, from: JSONEncoder().encode(attributes)) == attributes)
        for status in [RunActivityAttributes.Status.thinking, .streaming, .finishing, .reconnecting, .completed, .aborted, .failed] {
            let state = RunActivityAttributes.ContentState(agentName: "Main", startedAt: now, status: status)
            let bytes = try JSONEncoder().encode(state)
            #expect(try JSONDecoder().decode(RunActivityAttributes.ContentState.self, from: bytes) == state)
            #expect(bytes.count < 4_096)
        }
    }

    @Test func lifecycleAndChatSequencesAreIndependentAndTerminalWins() throws {
        var tracker = RunActivityTracker()
        func receive(_ frame: GatewayEventFrame, now: Date, agentName: (String) -> String) -> RunActivityTracker.Run? {
            tracker.receive(frame, now: now, agentName: agentName)
        }
        let start = try #require(receive(lifecycle("start", seq: 10), now: now, agentName: { _ in "Main" }))
        #expect(start.state.startedAt == Date(timeIntervalSince1970: 990))
        #expect(start.state.agentName == "Main")
        let streaming = receive(chat(.delta(.init(deltaText: "private text"))), now: now, agentName: { $0 })
        #expect(streaming?.state.status == .streaming)
        #expect(streaming?.state.startedAt == start.state.startedAt)
        #expect(receive(chat(.delta(.init(deltaText: "more private text")), seq: 2), now: now, agentName: { $0 }) == nil)
        #expect(receive(chat(.status(.init(phase: nil))), now: now, agentName: { $0 }) == nil)
        #expect(receive(lifecycle("finishing", seq: 11), now: now, agentName: { $0 })?.state.status == .finishing)
        #expect(receive(chat(.final(.init()), seq: 3), now: now, agentName: { $0 })?.state.status == .completed)
        #expect(tracker.runs.isEmpty)
        #expect(receive(lifecycle("start", seq: 12), now: now, agentName: { $0 }) == nil)
    }

    @Test(arguments: ["end", "error"])
    func lifecycleEndsWithoutAChatFinal(phase: String) {
        var tracker = RunActivityTracker()
        func receive(_ frame: GatewayEventFrame, now: Date, agentName: (String) -> String) -> RunActivityTracker.Run? {
            tracker.receive(frame, now: now, agentName: agentName)
        }
        _ = receive(lifecycle("start", seq: 1), now: now, agentName: { $0 })
        #expect(receive(lifecycle(phase, seq: 2, key: nil), now: now, agentName: { $0 })?.state.status.isTerminal == true)
        #expect(tracker.runs.isEmpty)
    }

    @Test func abortAndErrorAreTerminalAndUnknownEventsAreIgnored() {
        var tracker = RunActivityTracker()
        func receive(_ frame: GatewayEventFrame, now: Date, agentName: (String) -> String) -> RunActivityTracker.Run? {
            tracker.receive(frame, now: now, agentName: agentName)
        }
        #expect(receive(chat(.aborted(.init())), now: now, agentName: { $0 })?.state.status == .aborted)
        #expect(receive(chat(.error(.init()), run: "failed"), now: now, agentName: { $0 })?.state.status == .failed)
        #expect(receive(chat(.unknown("new"), run: "unknown"), now: now, agentName: { $0 }) == nil)
        #expect(receive(lifecycle("start", seq: 2, key: nil), now: now, agentName: { $0 }) == nil)
    }

    @Test func suspendedRunsBecomeUncertainAndCatchUpEndsOnlyFinishedRuns() {
        var tracker = RunActivityTracker()
        func receive(_ frame: GatewayEventFrame, now: Date, agentName: (String) -> String) -> RunActivityTracker.Run? {
            tracker.receive(frame, now: now, agentName: agentName)
        }
        _ = receive(chat(.status(.init(phase: nil))), now: now, agentName: { $0 })
        _ = receive(chat(.status(.init(phase: nil)), run: "other", key: "agent:other:chat"), now: now, agentName: { $0 })
        let paused = tracker.disconnect()
        #expect(paused.allSatisfy { $0.state.status == .reconnecting })
        let active = tracker.reconcile(sessionKey: "agent:main:main", activeRunIDs: ["run"])
        #expect(active.map(\.state.status) == [.thinking])
        let ended = tracker.reconcile(sessionKey: "agent:main:main", activeRunIDs: [])
        #expect(ended.map(\.state.status) == [.completed])
        #expect(tracker.runs.keys.sorted() == ["other"])
        #expect(receive(chat(.delta(.init(deltaText: "late")), seq: 2), now: now, agentName: { $0 }) == nil)
    }

    @Test func yieldedFinalKeepsTheRunActive() {
        var tracker = RunActivityTracker()
        func receive(_ frame: GatewayEventFrame, now: Date, agentName: (String) -> String) -> RunActivityTracker.Run? {
            tracker.receive(frame, now: now, agentName: agentName)
        }
        #expect(receive(chat(.final(.init(yielded: true))), now: now, agentName: { $0 })?.state.status == .thinking)
        #expect(tracker.runs.count == 1)
    }

    @Test func activityLinkRoundTripsAndRejectsUnrecognizedRoutes() throws {
        let attributes = RunActivityAttributes(runID: "run", sessionKey: "agent:main:chat/a?b&c")
        let url = try #require(attributes.sessionURL)
        #expect(RunActivityAttributes.sessionKey(from: url) == attributes.sessionKey)
        for raw in ["https://session?key=a", "fancyclaw://session?key=", "fancyclaw://session?key=a&key=b", "fancyclaw://session/path?key=a"] {
            #expect(RunActivityAttributes.sessionKey(from: try #require(URL(string: raw))) == nil)
        }
    }

    @Test @MainActor func driverGetsStartPauseEndAndStop() async {
        let driver = RecordingDriver()
        let store = RunActivityStore(connection: GatewayConnection(identity: .generate()), driver: driver, agentName: { $0 })
        await store.receive(chat(.status(.init(phase: nil))))
        await store.connectionDidDisconnect()
        await store.reconcile(sessionKey: "agent:main:main", activeRunIDs: [])
        await store.stop()
        #expect(driver.states == [.thinking, .reconnecting, .completed])
        #expect(driver.stopped)
    }
}

@MainActor private final class RecordingDriver: RunActivityDriver {
    var states: [RunActivityAttributes.Status] = []
    var stopped = false
    func publish(_ run: RunActivityTracker.Run) async { states.append(run.state.status) }
    func endAll() async { stopped = true }
}
