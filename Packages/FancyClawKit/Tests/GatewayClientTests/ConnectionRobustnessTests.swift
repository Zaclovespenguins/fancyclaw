import Foundation
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing

@Suite("Connection robustness", .serialized)
struct ConnectionRobustnessTests {
    // B6: a startup retry that wakes after a newer connect finished must not replace the live socket.
    @Test(.timeLimit(.minutes(1)))
    func staleStartupRetryDoesNotReplaceTheLiveSocket() async throws {
        let failure = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "error-startup-unavailable.res").error)
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.failure(failure), .hello(hello), .hello(hello)])
        fake.reply(to: "sessions.list", with: .object(["ok": .bool(true)]))
        let url = try await fake.start()
        defer { fake.stop() }
        let gate = SleepGate()
        let connection = GatewayConnection(identity: .generate(), timing: gate.timing)
        let stale = Task { try await connection.connect(to: url, token: "test-token") }
        await gate.waitUntilSleeping()
        // Connect B runs to completion while A is parked in its retry sleep.
        _ = try await connection.connect(to: url, token: "test-token")
        gate.release()
        do {
            _ = try await stale.value
            Issue.record("The stale attempt should have been cancelled")
        } catch is CancellationError { }
        let value: JSONValue = try await connection.request("sessions.list", params: Optional<JSONValue>.none,
                                                            returning: JSONValue.self, timeout: .seconds(3))
        #expect(value == .object(["ok": .bool(true)]))
        await connection.disconnect()
    }

    // B10: a Keychain failure after the handshake must not tear down the authenticated connection.
    @Test(.timeLimit(.minutes(1)))
    func keychainSaveFailureKeepsTheConnection() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.reply(to: "health", with: .bool(true))
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate(), identityStore: FailingTokenStore())
        _ = try await connection.connect(to: url, token: "test-token")
        let healthy: JSONValue = try await connection.request("health", params: Optional<JSONValue>.none,
                                                              returning: JSONValue.self, timeout: .seconds(3))
        #expect(healthy == .bool(true))
        await connection.disconnect()
    }

    // B11: caller cancellation fails the RPC promptly instead of waiting out the timeout.
    @Test(.timeLimit(.minutes(1)))
    func cancellingTheCallerFailsTheRequestPromptly() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        let call = Task {
            try await connection.request("never.answered", params: Optional<JSONValue>.none,
                                         returning: JSONValue.self, timeout: .seconds(15))
        }
        try await Task.sleep(for: .milliseconds(100))
        let clock = ContinuousClock()
        let start = clock.now
        call.cancel()
        do {
            _ = try await call.value
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
        #expect(start.duration(to: clock.now) < .seconds(1))
        await connection.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func unansweredRequestStillTimesOutOnInjectedTiming() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let gate = SleepGate()
        let connection = GatewayConnection(identity: .generate(), timing: gate.timing)
        _ = try await connection.connect(to: url, token: "test-token")
        let call = Task {
            try await connection.request("never.answered", params: Optional<JSONValue>.none,
                                         returning: JSONValue.self, timeout: .seconds(15))
        }
        await gate.waitUntilSleeping()
        gate.release()
        do {
            _ = try await call.value
            Issue.record("Expected a timeout")
        } catch ConnectionError.timedOut { }
        await connection.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func answeredRequestCancelsItsTimeout() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.reply(to: "health", with: .bool(true))
        let url = try await fake.start()
        defer { fake.stop() }
        let gate = SleepGate()
        let connection = GatewayConnection(identity: .generate(), timing: gate.timing)
        _ = try await connection.connect(to: url, token: "test-token")
        let value: JSONValue = try await connection.request("health", params: Optional<JSONValue>.none,
                                                            returning: JSONValue.self, timeout: .seconds(15))
        #expect(value == .bool(true))
        // Releasing the parked timeout sleep after the reply must not disturb the connection.
        await gate.waitUntilSleeping()
        #expect(gate.wasCancelled)
        await connection.disconnect()
    }
}

private struct FailingTokenStore: DeviceTokenStoring {
    func deviceToken(deviceID: String, role: String) throws -> String? { nil }
    func saveDeviceToken(_ token: String, deviceID: String, role: String) throws { throw KeychainError(-25_300) }
}

/// Injected sleep whose first call parks until released (recording cancellation); later calls sleep for real.
private final class SleepGate: Sendable {
    private let entered: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private let released: AsyncStream<Void>
    private let releasedContinuation: AsyncStream<Void>.Continuation
    private let cancelled = Flag()
    private let calls = Counter()

    init() {
        (entered, enteredContinuation) = AsyncStream.makeStream()
        (released, releasedContinuation) = AsyncStream.makeStream()
    }

    var wasCancelled: Bool { cancelled.value }
    func release() { releasedContinuation.finish() }
    func waitUntilSleeping() async { for await _ in entered { return } }

    var timing: GatewayTiming {
        GatewayTiming(now: { .zero }, sleep: { [self] duration in
            guard calls.next() == 1 else { return try await Task.sleep(for: duration) }
            enteredContinuation.yield()
            await withTaskCancellationHandler {
                for await _ in released {}
            } onCancel: { cancelled.set() }
            try Task.checkCancellation()
        })
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}
