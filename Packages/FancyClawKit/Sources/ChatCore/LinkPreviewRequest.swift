import Foundation
import GatewayClient

/// A bounded callback-backed request. Timeout/cancellation resumes immediately, even if a provider finishes late.
@MainActor final class LinkPreviewRequest<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, any Error>?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var cancelProvider: (@MainActor @Sendable () -> Void)?
    private var wasCancelled = false

    func load(timeout: Duration, timing: GatewayTiming,
              fetch: @escaping @MainActor @Sendable () async throws -> Value,
              cancel: @escaping @MainActor @Sendable () -> Void) async throws -> Value? {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !wasCancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                cancelProvider = cancel
                work = Task { [weak self] in
                    do {
                        let value = try await fetch()
                        try Task.checkCancellation()
                        self?.finish(.success(value))
                    } catch { self?.finish(.failure(error)) }
                }
                deadline = Task { [weak self] in
                    do {
                        try await timing.sleep(timeout)
                        try Task.checkCancellation()
                        self?.finish(.success(nil), cancellingProvider: true)
                    } catch { /* A completed request cancels its deadline. */ }
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    private func cancel() {
        wasCancelled = true
        finish(.failure(CancellationError()), cancellingProvider: true)
    }

    private func finish(_ result: Result<Value?, any Error>, cancellingProvider: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        if cancellingProvider {
            work?.cancel()
            cancelProvider?()
        }
        work = nil
        cancelProvider = nil
        continuation.resume(with: result)
    }
}
