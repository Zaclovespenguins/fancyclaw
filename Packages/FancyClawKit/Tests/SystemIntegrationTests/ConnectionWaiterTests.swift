import GatewayClient
import SystemIntegration
import Testing

@Suite("Intent connection wait and foreground ordering")
struct ConnectionWaiterTests {
    /// Sleeps advance a scripted status sequence instead of real time.
    @MainActor private final class Script {
        var statuses: [ConnectionStatus]
        var index = 0
        var sleeps: [Duration] = []
        init(_ statuses: [ConnectionStatus]) { self.statuses = statuses }
        var current: ConnectionStatus { statuses[min(index, statuses.count - 1)] }
        func advance(_ d: Duration) { sleeps.append(d); index += 1 }
    }

    @Test @MainActor func returnsOnceReconnectingBecomesConnected() async throws {
        let script = Script([.offline, .reconnecting, .connected])
        let waiter = ConnectionWaiter(timeout: .seconds(10), pollInterval: .milliseconds(100),
                                      sleep: { script.advance($0) })
        try await waiter.waitUntilConnected(status: { script.current }, hasConnection: { true })
        #expect(script.index == 2)
    }

    @Test @MainActor func timesOutWhileOnlyReconnecting() async {
        let script = Script([.reconnecting])
        let waiter = ConnectionWaiter(timeout: .seconds(10), pollInterval: .milliseconds(100),
                                      sleep: { script.advance($0) })
        await #expect(throws: IntentError.self) {
            try await waiter.waitUntilConnected(status: { script.current }, hasConnection: { true })
        }
        #expect(script.sleeps.count == 100)
    }

    @Test @MainActor func failsImmediatelyWithoutAConfiguredConnection() async {
        let script = Script([.offline])
        let waiter = ConnectionWaiter(timeout: .seconds(10), pollInterval: .milliseconds(100),
                                      sleep: { script.advance($0) })
        await #expect(throws: IntentError.self) {
            try await waiter.waitUntilConnected(status: { script.current }, hasConnection: { false })
        }
        #expect(script.sleeps.isEmpty)
    }

    @Test @MainActor func latestForegroundValueReachesLifecycleBeforeActivityWork() async {
        var lifecycleCalls: [Bool] = []
        var gate: CheckedContinuation<Void, Never>?
        var activityCalls = 0
        let coordinator = ForegroundCoordinator(
            lifecycle: { lifecycleCalls.append($0) },
            backgroundActivities: { activityCalls += 1; await withCheckedContinuation { gate = $0 } })
        let background = Task { await coordinator.set(false) }
        await Task.yield()
        let foreground = Task { await coordinator.set(true) }
        await foreground.value
        #expect(lifecycleCalls == [false, true])
        #expect(coordinator.isForeground)
        gate?.resume()
        await background.value
        #expect(lifecycleCalls == [false, true])
    }
}
