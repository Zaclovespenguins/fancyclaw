import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import os
import TestSupport
import Testing

@Suite("Exec approvals", .serialized) @MainActor
struct ApprovalStoreTests {
    private let date = Date(timeIntervalSince1970: 2_000_000_000)

    private func request(_ id: String = "approval", session: String? = "main", runID: String? = nil,
                         allowed: [ApprovalDecision] = [.allowOnce, .deny], expiry: Int = 120_000) -> GatewayEventFrame {
        .init(event: .execApprovalRequested(.init(id: id, createdAtMs: 2_000_000_000_000,
            expiresAtMs: 2_000_000_000_000 + expiry, request: .init(command: "swift --version",
                allowedDecisions: allowed, sessionKey: session, runId: runID))))
    }

    private func store(resolve: @escaping @Sendable (ExecApprovalResolveParams) async throws -> Void = { _ in }) -> ApprovalStore {
        ApprovalStore(scopes: [.approvals], now: { Date(timeIntervalSince1970: 2_000_000_000) }, resolve: resolve)
    }

    @Test func localDecisionThenDuplicateEventsAreIdempotent() async {
        let store = store()
        defer { store.stop() }
        store.receive(request())
        store.receive(request())
        #expect(store.approvals.count == 1)
        #expect(store.pendingCount(for: "main") == 1)
        await store.resolve(id: "approval", decision: .allowOnce)
        let resolved = GatewayEventFrame(event: .execApprovalResolved(.init(id: "approval", decision: .allowOnce)))
        store.receive(resolved)
        store.receive(resolved)
        store.receive(request())
        #expect(store.approvals.count == 1)
        #expect(store.approvals[0].status == .resolved(.allowOnce))
        #expect(store.pendingCount() == 0)
    }

    @Test func sessionRoutingBadgesAndSessionlessRunAssociation() {
        let store = store()
        defer { store.stop() }
        store.receive(request("a"))
        store.receive(request("b", session: "other"))
        store.receive(request("c", session: nil, runID: "run"))
        #expect(store.approvals(for: "main").map(\.id) == ["a", "c"])
        #expect(store.pendingCount(for: "other") == 1)
        store.receive(.init(event: .agent(.init(runId: "run", seq: 1, stream: "tool", sessionKey: "other", data: [:]))))
        #expect(store.approvals(for: "main").map(\.id) == ["a"])
        #expect(store.pendingCount(for: "other") == 2)
        store.receive(.init(event: .chat(.init(runId: "run2", sessionKey: "third", seq: 1, state: .status(.init(phase: nil))))))
        store.receive(request("d", session: nil, runID: "run2"))
        #expect(store.approvals(for: "third").map(\.id) == ["d"])
    }

    @Test func resolvedBeforeRequestedNeverReopens() {
        let store = store()
        defer { store.stop() }
        store.receive(.init(event: .execApprovalResolved(.init(id: "approval", decision: .deny))))
        store.receive(request())
        #expect(store.approvals[0].status == .resolved(.deny))
        #expect(store.pendingCount() == 0)
    }

    @Test func doubleTapAndRemoteResolutionDuringRPC() async {
        let rpc = SuspendedApprovalRPC()
        let store = store { params in try await rpc.resolve(params) }
        defer { store.stop() }
        store.receive(request())
        let first = Task { await store.resolve(id: "approval", decision: .allowOnce) }
        for _ in 0..<100 where rpc.calls == 0 { await Task.yield() }
        #expect(store.approvals[0].status == .resolving)
        await store.resolve(id: "approval", decision: .deny)
        #expect(rpc.calls == 1)
        store.receive(.init(event: .execApprovalResolved(.init(id: "approval", decision: .deny))))
        rpc.finish(throwing: ConnectionError.disconnected)
        await first.value
        #expect(store.approvals[0].status == .resolved(.deny))
        #expect(store.approvals[0].errorMessage == nil)
    }

    @Test(arguments: [ApprovalDecision.allowOnce, .deny])
    func remoteDecisionWinsOverSuccessfulRPC(decision: ApprovalDecision) async {
        let rpc = SuspendedApprovalRPC()
        let store = store { params in try await rpc.resolve(params) }
        defer { store.stop() }
        store.receive(request())
        let task = Task { await store.resolve(id: "approval", decision: .allowOnce) }
        for _ in 0..<100 where rpc.calls == 0 { await Task.yield() }
        store.receive(.init(event: .execApprovalResolved(.init(id: "approval", decision: decision))))
        rpc.finish()
        await task.value
        #expect(store.approvals[0].status == .resolved(decision))
    }

    @Test func unknownOrUnavailableDecisionNeverSentAndDenyAlwaysAllowed() async {
        let rpc = ApprovalRPCRecorder()
        let store = store { params in await rpc.record(params) }
        defer { store.stop() }
        store.receive(request(allowed: [.allowOnce, .unknown("future")]))
        await store.resolve(id: "approval", decision: .unknown("future"))
        await store.resolve(id: "approval", decision: .allowAlways)
        #expect(await rpc.calls.isEmpty)
        await store.resolve(id: "approval", decision: .deny)
        #expect(await rpc.calls.map(\.decision) == [.deny])
    }

    @Test func expiryUpdatesWithoutNetworkAndPreventsSending() async {
        let clock = ApprovalTestClock(date: date)
        let rpc = ApprovalRPCRecorder()
        let store = ApprovalStore(scopes: [.approvals], timing: clock.timing, now: { clock.date }) { params in
            await rpc.record(params)
        }
        defer { store.stop(); clock.advance(.seconds(1)) }
        store.receive(request(expiry: 1000))
        for _ in 0..<100 where !clock.hasSleeper { await Task.yield() }
        clock.advance(.seconds(1))
        for _ in 0..<100 where store.approvals[0].status != .expired { await Task.yield() }
        #expect(store.approvals[0].status == .expired)
        #expect(store.currentDate == date.addingTimeInterval(1))
        #expect(store.pendingCount() == 0)
        await store.resolve(id: "approval", decision: .allowOnce)
        #expect(await rpc.calls.isEmpty)
        store.receive(request("already-expired", expiry: 0))
        #expect(store.approvals.last?.status == .expired)
    }

    @Test func missingScopeDisablesDecisionsWithGuidance() async {
        let store = store { _ in
            throw GatewayErrorShape(code: .forbidden, message: "Forbidden", details: ["code": "MISSING_SCOPE", "missingScope": "operator.approvals"])
        }
        defer { store.stop() }
        store.receive(request())
        await store.resolve(id: "approval", decision: .allowOnce)
        #expect(!store.hasApprovalScope)
        #expect(store.permissionMessage?.contains("operator.approvals") == true)
        #expect(store.approvals[0].status == .pending)
        store.updateScopes([.read])
        #expect(!store.hasApprovalScope)
        store.updateScopes([.approvals])
        #expect(store.hasApprovalScope)
        #expect(store.permissionMessage == nil)
        #expect(store.approvals[0].errorMessage == nil)
    }

    @Test func initiallyMissingScopeDoesNotSend() async {
        let rpc = ApprovalRPCRecorder()
        let store = store { params in await rpc.record(params) }
        defer { store.stop() }
        store.updateScopes([.read, .write])
        store.receive(request())
        await store.resolve(id: "approval", decision: .deny)
        #expect(await rpc.calls.isEmpty)
        #expect(store.permissionMessage != nil)
    }

    @Test func notFoundIsAlreadyHandledAndNetworkFailureCanRetry() async {
        let store = store { _ in throw GatewayErrorShape(code: .approvalNotFound, message: "Gone") }
        defer { store.stop() }
        store.receive(request())
        await store.resolve(id: "approval", decision: .allowOnce)
        #expect(store.approvals[0].status == .alreadyHandled)
        #expect(store.pendingCount() == 0)
        store.receive(request())
        #expect(store.approvals[0].status == .alreadyHandled)

        let rpc = ApprovalRPCRecorder()
        let retry = self.store { params in
            await rpc.record(params)
            if await rpc.calls.count == 1 { throw ConnectionError.disconnected }
        }
        defer { retry.stop() }
        retry.receive(request())
        await retry.resolve(id: "approval", decision: .deny)
        #expect(retry.approvals[0].status == .pending)
        #expect(retry.approvals[0].errorMessage != nil)
        await retry.resolve(id: "approval", decision: .deny)
        #expect(retry.approvals[0].status == .resolved(.deny))
        #expect(retry.approvals[0].errorMessage == nil)
    }

    @Test func stoppedStoreIgnoresLateRPC() async {
        let rpc = SuspendedApprovalRPC()
        let store = store { params in try await rpc.resolve(params) }
        store.receive(request())
        let task = Task { await store.resolve(id: "approval", decision: .allowOnce) }
        for _ in 0..<100 where rpc.calls == 0 { await Task.yield() }
        store.stop()
        rpc.finish()
        await task.value
        #expect(store.approvals[0].status == .pending)
    }

    @Test(arguments: [ApprovalDecision.allowOnce, .allowAlways, .deny])
    func fakeGatewayRoundTrip(decision: ApprovalDecision) async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = ApprovalStore(connection: connection)
        async let firstStart: Void = store.start()
        async let secondStart: Void = store.start()
        _ = await (firstStart, secondStart)
        defer { store.stop() }
        let created = Int(Date.now.timeIntervalSince1970 * 1000)
        fake.requestApproval(.init(id: "roundtrip", createdAtMs: created, expiresAtMs: created + 120_000,
            request: .init(command: "pwd", sessionKey: "other")))
        for _ in 0..<50 where store.approvals.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.pendingCount(for: "other") == 1)
        await store.resolve(id: "roundtrip", decision: decision)
        #expect(store.approvals.first?.status == .resolved(decision))
        #expect(store.pendingCount() == 0)
        #expect(fake.receivedConnects.first?.scopes?.contains(.approvals) == true)
        let rpc = try #require(fake.receivedRequests.first { $0.method == "exec.approval.resolve" })
        #expect(rpc.params == .object(["id": "roundtrip", "decision": .string(decision.rawValue)]))
        #expect(fake.recordedFailures.isEmpty)
        await connection.disconnect()
    }

    @Test func fakeGatewayMissingScopeResponse() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.fail("exec.approval.resolve", with: .init(code: .forbidden, message: "Forbidden",
            details: ["code": "MISSING_SCOPE", "missingScope": "operator.approvals"]))
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = ApprovalStore(connection: connection, now: { Date(timeIntervalSince1970: 2_000_000_000) })
        await store.start()
        defer { store.stop() }
        store.receive(request())
        await store.resolve(id: "approval", decision: .deny)
        #expect(store.permissionMessage?.contains("operator.approvals") == true)
        #expect(!store.hasApprovalScope)
        await connection.disconnect()
    }
}

private actor ApprovalRPCRecorder {
    var calls: [ExecApprovalResolveParams] = []
    func record(_ params: ExecApprovalResolveParams) { calls.append(params) }
}

@MainActor private final class SuspendedApprovalRPC {
    var calls = 0
    private var continuation: CheckedContinuation<Void, any Error>?
    func resolve(_ params: ExecApprovalResolveParams) async throws {
        calls += 1
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(throwing error: (any Error)? = nil) {
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
        continuation = nil
    }
}

private final class ApprovalTestClock: Sendable {
    private struct Sleeper { let deadline: Duration; let continuation: CheckedContinuation<Void, Never> }
    private struct State { var now: Duration = .zero; var sleepers: [Sleeper] = [] }
    private let storage = OSAllocatedUnfairLock(initialState: State())
    private let origin: Date
    init(date: Date) { origin = date }
    var date: Date {
        let duration = storage.withLock { $0.now }.components
        return origin.addingTimeInterval(Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }
    var hasSleeper: Bool { storage.withLock { !$0.sleepers.isEmpty } }
    var timing: GatewayTiming {
        GatewayTiming(now: { self.storage.withLock { $0.now } }, sleep: { delay in
            await withCheckedContinuation { continuation in
                self.storage.withLock { state in
                    state.sleepers.append(Sleeper(deadline: state.now + delay, continuation: continuation))
                }
            }
        })
    }
    func advance(_ duration: Duration) {
        let ready = storage.withLock { state in
            state.now += duration
            let ready = state.sleepers.filter { $0.deadline <= state.now }
            state.sleepers.removeAll { $0.deadline <= state.now }
            return ready
        }
        for sleeper in ready { sleeper.continuation.resume() }
    }
}
