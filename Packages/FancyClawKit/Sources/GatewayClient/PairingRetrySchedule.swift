import Foundation

/// Bounded backoff for the five-minute manual device approval window.
public struct PairingRetrySchedule: Sendable {
    public var maximumDuration: Duration
    public var delays: [Duration]

    public init(maximumDuration: Duration = .seconds(300), delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(10)]) {
        self.maximumDuration = maximumDuration
        self.delays = delays.isEmpty ? [.seconds(1)] : delays
    }

    /// Returns the sleep before the next retry, or nil when approval has expired.
    public func delay(afterAttempt attempt: Int, elapsed: Duration) -> Duration? {
        let remaining = maximumDuration - elapsed
        guard remaining > .zero else { return nil }
        return min(delays[Swift.min(Swift.max(attempt, 0), delays.count - 1)], remaining)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
