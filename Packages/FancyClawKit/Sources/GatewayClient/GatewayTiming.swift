import Foundation

/// Type-erased Clock injection, shared by watchdogs and reconnect delays.
public struct GatewayTiming: Sendable {
    public var now: @Sendable () -> Duration
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(now: @escaping @Sendable () -> Duration,
                sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.now = now
        self.sleep = sleep
    }

    public init<C: Clock & Sendable>(_ clock: C) where C.Duration == Duration {
        let origin = clock.now
        now = { origin.duration(to: clock.now) }
        sleep = { try await clock.sleep(for: $0) }
    }

    public static var continuous: Self { Self(ContinuousClock()) }
}
