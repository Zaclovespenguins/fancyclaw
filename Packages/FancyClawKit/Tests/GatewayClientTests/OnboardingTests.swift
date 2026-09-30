import Foundation
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing

@Suite("Onboarding input and retry policy")
struct OnboardingTests {
    @Test func parsesSetupCodeAndPreservesContextPath() throws {
        let json = #"{"url":"wss://claw.example/gateway/","urls":["wss://backup.example/"],"bootstrapToken":"bootstrap","tlsFingerprint":"aa:bb","expiresAtMs":2000000000000}"#
        let code = Base64URL.encode(Data(json.utf8))
        let parsed = try SetupCode.parse(code, now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(parsed.profile.url.absoluteString == "wss://claw.example/gateway/")
        #expect(parsed.profile.bootstrapToken == "bootstrap")
        #expect(parsed.profile.tlsFingerprint == "aa:bb")
        #expect(parsed.urls.first?.host == "backup.example")
    }

    @Test func parsesHostForm() throws {
        let json = #"{"host":"gateway.local","port":19001,"tls":false,"contextPath":"/proxy","token":"shared"}"#
        let parsed = try SetupCode.parse(Base64URL.encode(Data(json.utf8)))
        #expect(parsed.profile.url.absoluteString == "ws://gateway.local:19001/proxy")
        #expect(parsed.profile.token == "shared")
    }

    @Test func rejectsExpiredAndMalformedSetupCodes() throws {
        let expired = #"{"url":"wss://claw.example/","expiresAtMs":1000}"#
        #expect(throws: SetupCodeError.expired) {
            try SetupCode.parse(Base64URL.encode(Data(expired.utf8)), now: Date(timeIntervalSince1970: 2))
        }
        #expect(throws: SetupCodeError.malformed) { try SetupCode.parse("not a setup code") }
        #expect(throws: SetupCodeError.missingURL) {
            try SetupCode.parse(Base64URL.encode(Data(#"{"token":"x"}"#.utf8)))
        }
        #expect(throws: SetupCodeError.malformed) {
            try SetupCode.parse(Base64URL.encode(Data(#"{"url":"wss://claw.example:99999/"}"#.utf8)))
        }
    }

    @Test(arguments: [
        ("wss://example.com/", true),
        ("ws://example.com/", false),
        ("ws://localhost:18789/", true),
        ("ws://host.local/", true),
        ("ws://gateway.ts.net/", true),
        ("ws://10.0.0.2/", true),
        ("ws://172.31.0.2/", true),
        ("ws://100.100.0.1/", true),
        ("ws://[fd12::1]/", true),
        ("ws://[fe80::1]/", true),
        ("ws://fc.example.com/", false),
        ("ws://fdocs.com/", false),
        ("ws://foo.10.1.2.3/", false),
        ("http://localhost/", false),
    ])
    func transportPolicy(urlString: String, expected: Bool) {
        guard let url = URL(string: urlString) else { Issue.record("Invalid test URL"); return }
        #expect(((try? TransportPolicy.validate(url)) != nil) == expected)
    }

    @Test func fakeGatewayMovesFromPendingPairingToApproved() async throws {
        let pairingError = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "error-pairing-required.res").error)
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.failure(pairingError), .hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        let requests = RetryRecorder()
        let result = try await PairingCoordinator(schedule: .init(maximumDuration: .seconds(30)),
            sleep: { _ in }, elapsed: { .zero }).connect(using: {
                try await connection.connect(to: url, token: "test-token")
            }, onWaiting: { requestID, _ in await requests.record(requestID) })
        #expect(result.server.connId == hello.server.connId)
        let expectedRequestID = try #require(pairingError.pairingRequestId)
        #expect(await requests.values == [expectedRequestID])
        #expect(fake.receivedConnects.count == 2)
        await connection.disconnect()
    }

    @Test func coordinatorStopsAtTheApprovalDeadline() async throws {
        let pairingError = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "error-pairing-required.res").error)
        let clock = ElapsedBox()
        let count = RetryCounter()
        let coordinator = PairingCoordinator(schedule: .init(maximumDuration: .seconds(1)),
            sleep: { _ in clock.advance(milliseconds: 1_000) },
            elapsed: { .milliseconds(clock.value) })
        do {
            _ = try await coordinator.connect(using: {
                await count.increment()
                throw pairingError
            })
            Issue.record("Expected the approval deadline to expire")
        } catch let error as GatewayErrorShape {
            #expect(error.pairingRequestId == pairingError.pairingRequestId)
        }
        #expect(await count.value == 1)
    }

    @Test func coordinatorHonorsCancellationBeforeConnecting() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let count = RetryCounter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PairingCoordinator().connect(using: {
                await count.increment()
                return hello
            })
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
        #expect(await count.value == 0)
    }

    @Test func retriesPairingWithBoundedBackoffUntilExpiry() {
        let schedule = PairingRetrySchedule(maximumDuration: .seconds(300),
                                            delays: [.seconds(1), .seconds(2), .seconds(4)])
        #expect(schedule.delay(afterAttempt: 0, elapsed: .seconds(0)) == .seconds(1))
        #expect(schedule.delay(afterAttempt: 1, elapsed: .seconds(0)) == .seconds(2))
        #expect(schedule.delay(afterAttempt: 5, elapsed: .seconds(0)) == .seconds(4))
        #expect(schedule.delay(afterAttempt: 0, elapsed: .milliseconds(299_500)) == .milliseconds(500))
        #expect(schedule.delay(afterAttempt: 0, elapsed: .seconds(300)) == nil)
    }
}

private actor RetryRecorder {
    private(set) var values: [String] = []
    func record(_ value: String) { values.append(value) }
}

private actor RetryCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private final class ElapsedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds = 0
    var value: Int { lock.withLock { milliseconds } }
    func advance(milliseconds amount: Int) { lock.withLock { milliseconds += amount } }
}
