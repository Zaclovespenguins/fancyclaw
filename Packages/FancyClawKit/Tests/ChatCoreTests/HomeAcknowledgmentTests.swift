@testable import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import Persistence
import TestSupport
import Testing

@Suite("Home acknowledgments", .serialized, .timeLimit(.minutes(1))) @MainActor
struct HomeAcknowledgmentTests {
    private func gateway() throws -> FakeGateway {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.enableSessions()
        fake.reply(to: "chat.send", with: try JSONValue(encoding: ChatSendResponse(runId: "accepted-run", status: .started)))
        return fake
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }

    @Test func rejectionRetainsOriginalAttachmentAndRetryUsesSameRowKeyAndPayload() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        fake.fail("chat.send", with: .init(code: .forbidden, message: "Rejected"))
        let connection = GatewayConnection(identity: .generate())
        let url = try await fake.start()
        _ = try await connection.connect(to: url, token: "test")
        let store = ConversationStore(connection: connection)
        let upload = try await AttachmentPipeline().prepare(data: Data("original upload".utf8), fileName: "Notes.txt", limits: nil)
        #expect(!(await store.sendAcknowledged("Task", attachments: [upload], idempotencyKey: "home-key")))
        let original = try #require(store.messages.first)
        #expect(original.deliveryFailed)
        #expect(original.attachments == [upload])
        fake.clearFailure(for: "chat.send")
        #expect(await store.sendAcknowledged("Task", attachments: [upload], idempotencyKey: "home-key"))
        #expect(store.messages.filter { $0.role == .user }.map(\.id) == [original.id])
        let sends = fake.receivedRequests.filter { $0.method == "chat.send" }
        #expect(sends.count == 2)
        #expect(sends.first?.params == sends.last?.params)
        #expect(await store.sendAcknowledged("Task", attachments: [upload], idempotencyKey: "home-key"))
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 2)
        await connection.disconnect()
    }

    @Test func concurrentJoinAndDifferentPayloadDoNotReplaceOrCancelOriginal() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        fake.pauseResponses(to: "chat.send")
        let connection = GatewayConnection(identity: .generate())
        let url = try await fake.start()
        _ = try await connection.connect(to: url, token: "test")
        let store = ConversationStore(connection: connection)
        let first = Task { await store.sendAcknowledged("Original", idempotencyKey: "key") }
        try await waitUntil { fake.receivedRequests.contains { $0.method == "chat.send" } }
        #expect(store.isSending(idempotencyKey: "key"))
        #expect(!(await store.sendAcknowledged("Changed", idempotencyKey: "key")))
        var joinStarted = false
        let join = Task { joinStarted = true; return await store.sendAcknowledged("Original", idempotencyKey: "key") }
        try await waitUntil { joinStarted }
        fake.resumeResponses(to: "chat.send")
        #expect(await first.value)
        #expect(await join.value)
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 1)
        #expect(store.messages.filter { $0.role == .user }.map(\.text) == ["Original"])
        await connection.disconnect()
    }

    @Test func reconnectAutomaticRetryCanBeJoinedAndLaterManualRetryIsNoOp() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        let store = ConversationStore(connection: connection)
        #expect(!(await store.sendAcknowledged("Reconnect", idempotencyKey: "reconnect-key")))
        let rowID = try #require(store.messages.first?.id)
        fake.pauseResponses(to: "chat.send")
        let url = try await fake.start()
        _ = try await connection.connect(to: url, token: "test")
        let refresh = Task { await store.refreshHistory() }
        try await waitUntil { fake.receivedRequests.contains { $0.method == "chat.send" } }
        var manualStarted = false
        let manual = Task { manualStarted = true; return await store.sendAcknowledged("Reconnect", idempotencyKey: "reconnect-key") }
        try await waitUntil { manualStarted }
        fake.resumeResponses(to: "chat.send")
        await refresh.value
        #expect(await manual.value)
        #expect(await store.sendAcknowledged("Reconnect", idempotencyKey: "reconnect-key"))
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 1)
        #expect(store.messages.filter { $0.role == .user }.map(\.id) == [rowID])
        await connection.disconnect()
    }

    @Test func canonicalConfirmationRejectsAssistantLookalikeAndUnrelatedSession() async throws {
        let connection = GatewayConnection(identity: .generate())
        let store = ConversationStore(connection: connection)
        #expect(!(await store.sendAcknowledged("Same words", idempotencyKey: "canonical-key")))
        store.receive(.init(event: .chat(.init(runId: "other-run", sessionKey: "another-session", seq: 1,
            state: .final(.init(message: ChatMessage(role: .user, content: [.text("Same words")], idempotencyKey: "canonical-key:user")))))))
        store.reconcileHistory([
            ChatMessage(role: .assistant, content: [.text("Same words")], idempotencyKey: "canonical-key:user"),
            ChatMessage(role: .user, content: [.text("Same words")], idempotencyKey: "canonical-key:user:extra")
        ])
        #expect(!(await store.sendAcknowledged("Same words", idempotencyKey: "canonical-key")))
        store.reconcileHistory([ChatMessage(role: .user, content: [.text("Same words")], idempotencyKey: "canonical-key:user", metadata: .init(id: "canonical-entry"))])
        #expect(await store.sendAcknowledged("Same words", idempotencyKey: "canonical-key"))
        #expect(store.messages.map(\.id) == ["canonical-entry"])
        store.invalidate()
        #expect(!(await store.sendAcknowledged("Same words", idempotencyKey: "canonical-key")))
    }

    @Test func canonicalEchoSettlesJoinedWaiterBeforeDelayedRPC() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        fake.pauseResponses(to: "chat.send")
        let connection = GatewayConnection(identity: .generate())
        let url = try await fake.start()
        _ = try await connection.connect(to: url, token: "test")
        let store = ConversationStore(connection: connection)
        let owner = Task { await store.sendAcknowledged("Echo", idempotencyKey: "echo-key") }
        try await waitUntil { fake.receivedRequests.contains { $0.method == "chat.send" } }
        var waiterStarted = false
        var waiterFinished = false
        let waiter = Task {
            waiterStarted = true
            let result = await store.sendAcknowledged("Echo", idempotencyKey: "echo-key")
            waiterFinished = true
            return result
        }
        try await waitUntil { waiterStarted }
        store.reconcileHistory([ChatMessage(role: .user, content: [.text("Echo")], idempotencyKey: "echo-key:user", metadata: .init(id: "echo-entry"))])
        try await waitUntil { waiterFinished }
        #expect(await waiter.value)
        #expect(store.isSending(idempotencyKey: "echo-key"))
        fake.resumeResponses(to: "chat.send")
        #expect(await owner.value)
        #expect(store.messages.map(\.id) == ["echo-entry"])
        await connection.disconnect()
    }

    @Test func cancelledWaiterLeavesSharedSubmissionIntactAndInvalidationSettlesOthers() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        fake.pauseResponses(to: "chat.send")
        let connection = GatewayConnection(identity: .generate())
        let url = try await fake.start()
        _ = try await connection.connect(to: url, token: "test")
        let store = ConversationStore(connection: connection)
        let owner = Task { await store.sendAcknowledged("Frozen", idempotencyKey: "cancel-key") }
        try await waitUntil { fake.receivedRequests.contains { $0.method == "chat.send" } }
        var cancelledStarted = false
        let cancelled = Task { cancelledStarted = true; return await store.sendAcknowledged("Frozen", idempotencyKey: "cancel-key") }
        try await waitUntil { cancelledStarted }
        cancelled.cancel()
        #expect(!(await cancelled.value))
        #expect(store.isSending(idempotencyKey: "cancel-key"))
        var remainingStarted = false
        let remaining = Task { remainingStarted = true; return await store.sendAcknowledged("Frozen", idempotencyKey: "cancel-key") }
        try await waitUntil { remainingStarted }
        store.invalidate()
        #expect(!(await remaining.value))
        fake.resumeResponses(to: "chat.send")
        #expect(!(await owner.value))
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 1)
        await connection.disconnect()
    }

    @Test func canonicalConfirmationWinsOverLateRPCError() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        fake.pauseResponses(to: "chat.send")
        fake.fail("chat.send", with: .init(code: .unavailable, message: "A stale send error"))
        let connection = GatewayConnection(identity: .generate())
        let url = try await fake.start()
        _ = try await connection.connect(to: url, token: "test")
        let store = ConversationStore(connection: connection)
        let owner = Task { await store.sendAcknowledged("Accepted", idempotencyKey: "accepted-key") }
        try await waitUntil { fake.receivedRequests.contains { $0.method == "chat.send" } }
        store.reconcileHistory([ChatMessage(role: .user, content: [.text("Accepted")], idempotencyKey: "accepted-key:user", metadata: .init(id: "accepted-key:user"))])
        fake.resumeResponses(to: "chat.send")
        #expect(await owner.value)
        #expect(store.errorMessage == nil)
        #expect(store.messages.first?.deliveryFailed == false)
        #expect(await store.sendAcknowledged("Accepted", idempotencyKey: "accepted-key"))
        #expect(fake.receivedRequests.filter { $0.method == "chat.send" }.count == 1)
        await connection.disconnect()
    }

    @Test func resetDuringSubscriptionPreventsOldTaskFromReachingChatSend() async throws {
        let fake = try gateway()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        let url = try await fake.start()
        _ = try await connection.connect(to: url, token: "test")
        let key = SessionKey.main.rawValue
        let cache = TranscriptCache(container: try TranscriptCache.makeContainer(inMemory: true), gateway: "home-reset")
        try cache.saveHistory(ChatHistoryPage(sessionKey: key, sessionId: "old-incarnation",
            messages: [ChatMessage(role: .assistant, content: [.text("Old history")], metadata: .init(id: "old-entry"))]))
        let store = ConversationStore(connection: connection, cache: cache)
        #expect(store.messages.map(\.id) == ["old-entry"])
        fake.pauseResponses(to: "sessions.messages.subscribe")
        let pending = Task { await store.sendAcknowledged("Old task", idempotencyKey: "old-task-key") }
        try await waitUntil { fake.receivedRequests.contains { $0.method == "sessions.messages.subscribe" } }
        #expect(store.isSending(idempotencyKey: "old-task-key"))
        #expect(store.messages.contains { $0.id == "old-task-key:user" })
        fake.seedSessions([SessionSummary(key: key, sessionId: "new-incarnation", agentId: "main")])
        fake.seedHistory([], sessionKey: key)
        // refreshHistory waits for the same paused subscription. Fetch the real canonical page directly,
        // then invoke its existing reducer so the reset can occur before subscription finishes.
        let page: ChatHistoryPage = try await connection.request("chat.history",
            params: ChatHistoryParams(sessionKey: key, limit: 100), returning: ChatHistoryPage.self)
        #expect(page.sessionId == "new-incarnation")
        store.applyPage(page)
        #expect(store.messages.isEmpty)
        fake.resumeResponses(to: "sessions.messages.subscribe")
        #expect(!(await pending.value))
        #expect(!fake.receivedRequests.contains { $0.method == "chat.send" })
        #expect(store.messages.isEmpty)
        await connection.disconnect()
    }
}
