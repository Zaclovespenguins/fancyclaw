import Foundation
import GatewayProtocol

/// Retries a pairing-required connection while exposing the pending request and remaining approval window.
public struct PairingCoordinator: Sendable {
    public typealias ConnectOperation = @Sendable () async throws -> HelloOK
    public typealias WaitingHandler = @Sendable (_ requestID: String, _ remaining: Duration) async -> Void
    public typealias Sleeper = @Sendable (_ duration: Duration) async throws -> Void
    public typealias ElapsedProvider = @Sendable () -> Duration

    private let schedule: PairingRetrySchedule
    private let sleep: Sleeper
    private let elapsed: ElapsedProvider

    public init(schedule: PairingRetrySchedule = PairingRetrySchedule(),
                sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
                elapsed: ElapsedProvider? = nil) {
        self.schedule = schedule
        self.sleep = sleep
        if let elapsed { self.elapsed = elapsed }
        else {
            let clock = ContinuousClock()
            let start = clock.now
            self.elapsed = { start.duration(to: clock.now) }
        }
    }

    public func connect(using operation: ConnectOperation, onWaiting: WaitingHandler = { _, _ in }) async throws -> HelloOK {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let hello = try await operation()
                try Task.checkCancellation()
                return hello
            } catch let error as GatewayErrorShape where error.pairingRequestId != nil {
                // The clipped final sleep ends at the deadline; the loop then makes one last attempt before this throws.
                let elapsedTime = elapsed()
                guard let delay = schedule.delay(afterAttempt: attempt, elapsed: elapsedTime),
                      let requestID = error.pairingRequestId else { throw error }
                await onWaiting(requestID, schedule.maximumDuration - elapsedTime)
                try await sleep(delay)
                attempt += 1
            }
        }
    }
}
