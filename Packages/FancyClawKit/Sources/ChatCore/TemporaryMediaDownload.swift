import Foundation
import GatewayProtocol
import Observation

/// Owns a file preview only for the lifetime of its visible card. Bytes never enter the transcript cache.
@MainActor @Observable
public final class TemporaryMediaDownload {
    public private(set) var isDownloading = false
    public private(set) var errorMessage: String?
    public private(set) var failureCount = 0
    public var previewURL: URL? {
        didSet {
            if let oldValue, oldValue != previewURL {
                try? FileManager.default.removeItem(at: oldValue.deletingLastPathComponent())
            }
        }
    }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    private let temporaryDirectory: URL

    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    @discardableResult
    public func start(media: ContentBlock.Media,
                      load: @escaping @Sendable (ContentBlock.Media) async throws -> Data) -> Task<Void, Never>? {
        guard !isDownloading else { return nil }
        let id = UUID()
        requestID = id
        isDownloading = true
        errorMessage = nil
        let task = Task { [weak self] in
            do {
                let bytes = try await load(media)
                // Some media providers finish even after cancellation. Discard those bytes before writing a file.
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                self.previewURL = try self.write(bytes, named: media.safeFileName)
                self.finish(id)
            } catch {
                guard let self, self.requestID == id else { return }
                if !(error is CancellationError) {
                    self.errorMessage = "Download failed. Try again."
                    self.failureCount += 1
                }
                self.finish(id)
            }
        }
        self.task = task
        return task
    }

    /// Called when the card leaves the screen. A late result cannot reopen Quick Look or leave a file behind.
    public func cancel() {
        requestID = nil
        task?.cancel()
        task = nil
        isDownloading = false
        previewURL = nil
    }

    private func finish(_ id: UUID) {
        guard requestID == id else { return }
        isDownloading = false
        requestID = nil
        task = nil
    }

    private func write(_ bytes: Data, named name: String) throws -> URL {
        let directory = temporaryDirectory.appending(path: "chat-download-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        do { try bytes.write(to: url, options: [.completeFileProtection]) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
        return url
    }
}
