import Foundation
import GatewayProtocol
import Testing
@testable import ChatCore

@MainActor struct TemporaryMediaDownloadTests {
    private let media = ContentBlock.Media(kind: .file, fileName: "../report.txt", artifactId: "report")

    @Test func downloadedPreviewIsPrivateTemporaryAndRemovedOnDismissal() async throws {
        let download = TemporaryMediaDownload()
        let bytes = Data("Report content".utf8)
        let task = try #require(download.start(media: media) { _ in bytes })
        await task.value
        let url = try #require(download.previewURL)
        let directory = url.deletingLastPathComponent()
        #expect(url.lastPathComponent == "report.txt")
        #expect(try Data(contentsOf: url) == bytes)
        #expect(!download.isDownloading)
        download.previewURL = nil
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func cancellationDiscardsAnUncooperativeLateResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "download-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let download = TemporaryMediaDownload(temporaryDirectory: directory)
        let gate = DownloadGate()
        let task = try #require(download.start(media: media) { _ in await gate.load() })
        await gate.waitUntilLoading()
        download.cancel()
        await gate.release()
        await task.value
        #expect(download.previewURL == nil)
        #expect(!download.isDownloading)
        #expect(download.errorMessage == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func failureCanBeRetriedAndDisappearanceRemovesThePreview() async throws {
        let download = TemporaryMediaDownload()
        let failed = try #require(download.start(media: media) { _ in throw URLError(.badServerResponse) })
        await failed.value
        #expect(download.errorMessage == "Download failed. Try again.")
        #expect(download.failureCount == 1)
        let retry = try #require(download.start(media: media) { _ in Data([1]) })
        await retry.value
        let directory = try #require(download.previewURL).deletingLastPathComponent()
        #expect(download.errorMessage == nil)
        download.cancel()
        #expect(download.previewURL == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

/// Deliberately ignores task cancellation, as a callback-backed provider may do.
private actor DownloadGate {
    private var continuation: CheckedContinuation<Data, Never>?
    private var loadingWaiter: CheckedContinuation<Void, Never>?

    func load() async -> Data {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            loadingWaiter?.resume()
            loadingWaiter = nil
        }
    }

    func waitUntilLoading() async {
        if continuation != nil { return }
        await withCheckedContinuation { loadingWaiter = $0 }
    }

    func release() {
        continuation?.resume(returning: Data("Late result".utf8))
        continuation = nil
    }
}
