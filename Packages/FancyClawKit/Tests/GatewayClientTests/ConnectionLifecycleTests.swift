import Foundation
import os
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing

@Suite("Connection recovery", .serialized)
struct ConnectionLifecycleTests {
    @Test func boundedExponentialBackoff() {
        let policy = ReconnectPolicy()
        #expect(policy.delay(attempt: 0, jitter: 0.5) == .seconds(1))
        #expect(policy.delay(attempt: 1, jitter: 0.5) == .seconds(2))
        #expect(policy.delay(attempt: 100, jitter: 1) == .seconds(30))
        #expect(policy.delay(attempt: -1, jitter: -1) == .milliseconds(800))
    }

    @Test func gapsRequestResyncButDuplicatesDoNot() async throws {
        let count = Counter()
        let lifecycle = ConnectionLifecycle(connection: GatewayConnection(identity: .generate()),
            resync: { await count.increment() })
        await lifecycle.receive(.init(event: .tick(.init(ts: 0)), seq: 4))
        await lifecycle.receive(.init(event: .tick(.init(ts: 0)), seq: 4))
        await lifecycle.receive(.init(event: .tick(.init(ts: 0)), seq: 3))
        await lifecycle.receive(.init(event: .tick(.init(ts: 0)), seq: 6))
        #expect(await count.value == 1)
        await lifecycle.stop()
    }

    @Test func missedTicksTriggerRecovery() async throws {
        let time = TestTime()
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let connection = GatewayConnection(identity: .generate())
        let lifecycle = ConnectionLifecycle(connection: connection, timing: time.timing)
        let url = try #require(URL(string: "ws://127.0.0.1:1"))
        await lifecycle.start(profile: .init(url: url), hello: hello)
        time.advance(.milliseconds(hello.policy.tickIntervalMs * 2))
        await lifecycle.checkLiveness()
        #expect(await lifecycle.status == .connected)
        time.advance(.milliseconds(1))
        await lifecycle.checkLiveness()
        #expect(await lifecycle.status == .reconnecting)
        await lifecycle.stop()
        await connection.disconnect()
    }

    @Test func shutdownHonorsRestartDelay() async throws {
        let time = TestTime()
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let lifecycle = ConnectionLifecycle(connection: GatewayConnection(identity: .generate()), timing: time.timing)
        await lifecycle.start(profile: .init(url: try #require(URL(string: "ws://127.0.0.1:1"))), hello: hello)
        await lifecycle.receive(.init(event: .shutdown(.init(reason: "restart", restartExpectedMs: 750))))
        for _ in 0..<1_000 {
            if time.delays.contains(.milliseconds(750)) { break }
            await Task.yield()
        }
        #expect(time.delays.contains(.milliseconds(750)))
        #expect(await lifecycle.status == .reconnecting)
        await lifecycle.stop()
    }

    @Test func failedReaderReconnectsInsteadOfKeepingDeadSocket() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello), .hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url)
        let lifecycle = ConnectionLifecycle(connection: connection)
        await lifecycle.start(profile: .init(url: url), hello: hello)
        fake.dropConnections()
        for _ in 0..<200 {
            if fake.receivedConnects.count == 2, await lifecycle.status == .connected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fake.receivedConnects.count == 2)
        #expect(await lifecycle.status == .connected)
        fake.reply(to: "health", with: .bool(true))
        let healthy: JSONValue = try await connection.request("health", params: Optional<JSONValue>.none,
                                                             returning: JSONValue.self)
        #expect(healthy == .bool(true))
        await lifecycle.stop()
        await connection.disconnect()
    }

    @Test func foregroundReconnectsAndRequestsResync() async throws {
        let count = Counter()
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello), .hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url)
        let lifecycle = ConnectionLifecycle(connection: connection, resync: { await count.increment() })
        await lifecycle.start(profile: .init(url: url), hello: hello)
        await lifecycle.setForeground(false)
        #expect(await lifecycle.status == .offline)
        await lifecycle.setForeground(true)
        for _ in 0..<100 {
            if await lifecycle.status == .connected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await lifecycle.status == .connected)
        #expect(fake.receivedConnects.count == 2)
        #expect(await count.value == 1)
        await lifecycle.stop()
        await connection.disconnect()
    }
}

private actor Counter {
    var value = 0
    func increment() { value += 1 }
}

private final class TestTime: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: State())
    private struct State { var time: Duration = .zero; var delays: [Duration] = [] }
    var delays: [Duration] { storage.withLock { $0.delays } }
    func advance(_ amount: Duration) { storage.withLock { $0.time += amount } }
    var timing: GatewayTiming {
        GatewayTiming(now: { self.storage.withLock { $0.time } }, sleep: { delay in
            self.storage.withLock { $0.delays.append(delay) }
            try await Task.sleep(for: .seconds(3_600))
        })
    }
}
