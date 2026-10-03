import Foundation
import GatewayClient

/// Completed metadata only, held in memory. Concurrent cards own independent requests and cancellation.
@MainActor public final class LinkPreviewCache<Value: Sendable> {
    private final class Entry: NSObject {
        let value: Value
        init(_ value: Value) { self.value = value }
    }
    private let cache = NSCache<NSURL, Entry>()

    public init(countLimit: Int = 40, totalCostLimit: Int = 24 * 1_024 * 1_024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    public func load(_ url: URL, timeout: Duration = .seconds(8), timing: GatewayTiming = .continuous,
                     fallback: Value, cost: @MainActor @Sendable (Value) -> Int = { _ in 1 },
                     fetch: @escaping @MainActor @Sendable () async throws -> Value,
                     cancel: @escaping @MainActor @Sendable () -> Void = {}) async throws -> Value {
        try Task.checkCancellation()
        if let cached = cache.object(forKey: url as NSURL) { return cached.value }
        let request = LinkPreviewRequest<Value>()
        let value: Value
        do {
            guard let completed = try await request.load(timeout: timeout, timing: timing, fetch: fetch, cancel: cancel) else {
                try Task.checkCancellation()
                return fallback
            }
            value = completed
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            return fallback
        }
        // Never cache a timeout fallback or late metadata for a card whose task was cancelled.
        try Task.checkCancellation()
        cache.setObject(Entry(value), forKey: url as NSURL, cost: max(1, cost(value)))
        return value
    }
}
