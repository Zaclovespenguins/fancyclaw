import Foundation
import GatewayClient
import Testing
@testable import ChatCore

@Suite(.timeLimit(.minutes(1))) @MainActor struct LinkPreviewLifecycleTests {
    private var url: URL { URL(string: "https://example.com/article")! }

    @Test func completedMetadataIsCachedAndFailureCanRetry() async throws {
        let cache = LinkPreviewCache<String>()
        let calls = PreviewCounters()
        #expect(try await cache.load(url, fallback: "example.com", fetch: { calls.fetches += 1; return "Article" }) == "Article")
        #expect(try await cache.load(url, fallback: "example.com", fetch: { calls.fetches += 1; return "Changed" }) == "Article")
        #expect(calls.fetches == 1)
        let failingURL = try #require(URL(string: "https://offline.example.com"))
        #expect(try await cache.load(failingURL, fallback: "offline.example.com", fetch: { throw URLError(.notConnectedToInternet) }) == "offline.example.com")
        #expect(try await cache.load(failingURL, fallback: "offline.example.com", fetch: { calls.fetches += 1; return "Recovered" }) == "Recovered")
        #expect(calls.fetches == 2)
    }

    @Test func cancellationStopsProviderAndDoesNotCacheLateMetadata() async throws {
        let cache = LinkPreviewCache<String>()
        let gate = PreviewGate<String>()
        let calls = PreviewCounters()
        let task = Task { try await cache.load(url, fallback: "example.com", fetch: {
            let value = await gate.load()
            calls.completions += 1
            return value
        }, cancel: { calls.cancellations += 1 }) }
        await gate.waitUntilLoading()
        task.cancel()
        do { _ = try await task.value; Issue.record("A cancelled preview returned metadata") }
        catch { #expect(error is CancellationError) }
        #expect(calls.cancellations == 1)
        await gate.release("Late metadata")
        while calls.completions == 0 { await Task.yield() }
        #expect(try await cache.load(url, fallback: "example.com", fetch: { "Fresh metadata" }) == "Fresh metadata")
    }

    @Test func timeoutCancelsProviderAndLateCompletionCannotReplaceFallback() async throws {
        let cache = LinkPreviewCache<String>()
        let gate = PreviewGate<String>()
        let deadline = PreviewGate<Void>()
        let calls = PreviewCounters()
        let timing = GatewayTiming(now: { .zero }, sleep: { _ in await deadline.load() })
        let task = Task { try await cache.load(url, timing: timing, fallback: "example.com", fetch: {
            let value = await gate.load()
            calls.completions += 1
            return value
        }, cancel: { calls.cancellations += 1 }) }
        await gate.waitUntilLoading()
        await deadline.waitUntilLoading()
        await deadline.release(())
        #expect(try await task.value == "example.com")
        #expect(calls.cancellations == 1)
        await gate.release("Late metadata")
        while calls.completions == 0 { await Task.yield() }
        #expect(try await cache.load(url, fallback: "fallback", fetch: { "Fresh metadata" }) == "Fresh metadata")
    }

    @Test func cancellingOneCardDoesNotCancelAnotherRequestForSameURL() async throws {
        let cache = LinkPreviewCache<String>()
        let first = PreviewGate<String>()
        let second = PreviewGate<String>()
        let calls = PreviewCounters()
        let cancelled = Task { try await cache.load(url, fallback: "example.com", fetch: { await first.load() },
                                                   cancel: { calls.cancellations += 1 }) }
        let visible = Task { try await cache.load(url, fallback: "example.com", fetch: { await second.load() },
                                                 cancel: { calls.cancellations += 100 }) }
        await first.waitUntilLoading()
        await second.waitUntilLoading()
        cancelled.cancel()
        _ = try? await cancelled.value
        #expect(calls.cancellations == 1)
        await first.release("Cancelled card")
        await second.release("Visible card")
        #expect(try await visible.value == "Visible card")
        #expect(calls.cancellations == 1)
    }

    @Test func disablingAndReenablingCannotPublishAnOlderCompletion() async {
        let presentation = LinkPreviewPresentation<String>()
        let old = PreviewGate<String>()
        let first = Task { await presentation.load { await old.load() } }
        await old.waitUntilLoading()
        presentation.cancel()
        #expect(presentation.value == nil)
        await presentation.load { "Re-enabled preview" }
        await old.release("Old preview")
        await first.value
        #expect(presentation.value == "Re-enabled preview")
    }

    @Test func cancelledPresentationTaskCannotPublishEvenWithUncooperativeProvider() async {
        let presentation = LinkPreviewPresentation<String>()
        let gate = PreviewGate<String>()
        let task = Task { await presentation.load { await gate.load() } }
        await gate.waitUntilLoading()
        task.cancel()
        await gate.release("Late preview")
        await task.value
        #expect(presentation.value == nil)
    }
}

@MainActor private final class PreviewCounters {
    var fetches = 0
    var cancellations = 0
    var completions = 0
}

/// Ignores cancellation deliberately, modeling an Objective-C completion that arrives after cancellation.
private actor PreviewGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func load() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilLoading() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
