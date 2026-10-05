import Foundation

/// A cancellation-safe bridge for NSItemProvider's data API, which has no async counterpart.
@MainActor final class LinkPreviewImageRequest {
    private var continuation: CheckedContinuation<Data?, Never>?
    private var progress: Progress?
    private var wasCancelled = false

    func load(_ provider: NSItemProvider, identifier: String) async -> Data? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !wasCancelled, !Task.isCancelled else { continuation.resume(returning: nil); return }
                self.continuation = continuation
                progress = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    Task { @MainActor in self.finish(data) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func cancel() {
        wasCancelled = true
        progress?.cancel()
        finish(nil)
    }

    private func finish(_ data: Data?) {
        guard let continuation else { return }
        self.continuation = nil
        progress = nil
        continuation.resume(returning: data)
    }
}
