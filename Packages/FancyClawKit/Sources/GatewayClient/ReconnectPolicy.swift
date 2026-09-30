import Foundation

public struct ReconnectPolicy: Sendable {
    public init() {}

    public func delay(attempt: Int, jitter: Double) -> Duration {
        let base = min(pow(2, Double(min(max(attempt, 0), 6))), 30)
        return .seconds(min(30, base * (0.8 + 0.4 * min(max(jitter, 0), 1))))
    }
}
