import Foundation
import Observation

/// Invalidating a card prevents an old completion from publishing after previews are disabled/re-enabled.
@MainActor @Observable public final class LinkPreviewPresentation<Value: Sendable> {
    public private(set) var value: Value?
    private var requestID: UUID?

    public init() {}

    public func load(_ operation: @MainActor @Sendable () async throws -> Value) async {
        let id = UUID()
        requestID = id
        value = nil
        do {
            let result = try await operation()
            try Task.checkCancellation()
            guard requestID == id else { return }
            value = result
        } catch { /* The domain placeholder remains usable when loading is cancelled. */ }
        if requestID == id { requestID = nil }
    }

    public func cancel() {
        requestID = nil
        value = nil
    }
}
