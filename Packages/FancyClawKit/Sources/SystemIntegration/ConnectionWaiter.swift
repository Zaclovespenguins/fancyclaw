import Foundation
import GatewayClient

/// Bounded wait for a recovering connection, used by intents that foreground the app from a disconnected state.
/// Time is injected: the loop counts `pollInterval` sleeps against `timeout`, so tests need no real clock.
@MainActor public struct ConnectionWaiter {
    private let timeout: Duration
    private let pollInterval: Duration
    private let sleep: @MainActor (Duration) async throws -> Void

    public init(timeout: Duration = .seconds(10), pollInterval: Duration = .milliseconds(100),
                sleep: @escaping @MainActor (Duration) async throws -> Void) {
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    public init(timeout: Duration = .seconds(10), pollInterval: Duration = .milliseconds(100), timing: GatewayTiming) {
        self.init(timeout: timeout, pollInterval: pollInterval, sleep: { try await timing.sleep($0) })
    }

    /// Returns when `status` reads `.connected`. Throws `IntentError.notConnected` at once without a configured
    /// connection, or after `timeout` of waiting.
    public func waitUntilConnected(status: () -> ConnectionStatus, hasConnection: () -> Bool) async throws {
        guard hasConnection() else { throw IntentError.notConnected }
        var waited = Duration.zero
        while status() != .connected {
            guard waited < timeout else { throw IntentError.notConnected }
            do { try await sleep(pollInterval) } catch { throw IntentError.notConnected }
            waited += pollInterval
        }
    }
}

/// Serializes scene-phase transitions so the latest value wins. The lifecycle sees every value in call order,
/// before any slow Live Activity work; stale background cleanup is skipped if the app is foreground again.
@MainActor public final class ForegroundCoordinator {
    public private(set) var isForeground = true
    private let lifecycle: @MainActor (Bool) async -> Void
    private let backgroundActivities: @MainActor () async -> Void

    public init(lifecycle: @escaping @MainActor (Bool) async -> Void,
                backgroundActivities: @escaping @MainActor () async -> Void) {
        self.lifecycle = lifecycle
        self.backgroundActivities = backgroundActivities
    }

    public func set(_ value: Bool) async {
        isForeground = value
        await lifecycle(value)
        if !value && !isForeground { await backgroundActivities() }
    }
}
