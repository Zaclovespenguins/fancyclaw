import Foundation
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing
@testable import ChatCore

@Suite("Conversation reducer", .serialized)
struct ConversationStoreTests {
    @Test @MainActor func fixtureDeltasAppendAndReplaceSnapshots() throws {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        store.receive(try Fixtures.decode(GatewayEventFrame.self, from: "chat-delta.event"))
        #expect(store.messages.count == 1)
        #expect(store.messages[0].text == "You're using ")
        #expect(store.messages[0].isStreaming)

        store.receive(try Fixtures.decode(GatewayEventFrame.self, from: "chat-delta-replace.event"))
        #expect(store.messages[0].text == "You are using **160 GB**")
        #expect(store.isStreaming)
    }

    @Test @MainActor func duplicateAndOutOfOrderEventsAreIgnored() throws {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        let delta = try Fixtures.decode(GatewayEventFrame.self, from: "chat-delta.event")
        store.receive(delta)
        store.receive(delta)
        #expect(store.messages[0].text == "You're using ")

        store.receive(try Fixtures.decode(GatewayEventFrame.self, from: "chat-final.event"))
        #expect(!store.isStreaming)
        let finalText = store.messages.first(where: { $0.role == .assistant })?.text
        store.receive(delta)
        #expect(store.messages.first(where: { $0.role == .assistant })?.text == finalText)
    }

    @Test @MainActor func replacementWithoutSnapshotReplacesBuffer() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "run", sessionKey: store.sessionKey, seq: 1,
            state: .delta(.init(deltaText: "partial"))))))
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "run", sessionKey: store.sessionKey, seq: 2,
            state: .delta(.init(deltaText: "corrected", replace: true))))))
        #expect(store.messages.last?.text == "corrected")
    }

    @Test @MainActor func finalWithoutDeltasCreatesCompletedAssistantMessage() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "run", sessionKey: store.sessionKey, seq: 1,
            state: .final(.init(message: ChatMessage(role: .assistant, content: [.text("complete")])))))))
        #expect(store.messages == [ConversationMessage(id: "run:assistant", role: .assistant, text: "complete")])
        #expect(!store.isStreaming)
    }

    @Test @MainActor func abortedAndErrorEventsSettleTheRun() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "aborted", sessionKey: store.sessionKey, seq: 1,
            state: .delta(.init(deltaText: "partial"))))))
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "aborted", sessionKey: store.sessionKey, seq: 2,
            state: .aborted(.init(errorMessage: "cancelled"))))))
        #expect(!store.messages.last!.isStreaming)
        #expect(!store.isStreaming)

        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "failed", sessionKey: store.sessionKey, seq: 1,
            state: .error(.init(errorMessage: "raw provider error", errorKind: .rateLimit))))))
        #expect(store.errorMessage == "The service is busy. Try again in a moment.")
        #expect(!store.isStreaming)
    }

    @Test @MainActor func ignoresOtherSessionsAndAgentEvents() throws {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        let wrongSession = GatewayEventFrame(event: .chat(ChatEvent(
            runId: "run", sessionKey: "agent:other:main", seq: 1,
            state: .delta(.init(deltaText: "wrong")))))
        store.receive(wrongSession)
        store.receive(GatewayEventFrame(event: .unknown(name: "agent", payload: nil)))
        #expect(store.messages.isEmpty)
    }

    @Test @MainActor func terminalEventBeforeAcknowledgementClearsAdoptedRun() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        let localID = "local-key"
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: localID, sessionKey: store.sessionKey, seq: 1,
            state: .status(.init(phase: nil))))))
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "server-run", sessionKey: store.sessionKey, seq: 1,
            state: .final(.init(message: ChatMessage(role: .assistant, content: [.text("done")])))))))
        #expect(store.isStreaming)

        store.adopt(ChatSendResponse(runId: "server-run", status: .started), idempotencyKey: localID)
        #expect(!store.isStreaming)
        #expect(store.messages.last?.text == "done")
    }

    @Test @MainActor func historyStableAssistantIDRemainsCanonicalDuringStreaming() {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "runA", sessionKey: store.sessionKey, seq: 1,
            state: .delta(.init(deltaText: "partial"))))))

        store.reconcileHistory([ChatMessage(
            role: .assistant, content: [.text("snapshot")],
            metadata: .init(id: "entryA", runId: "runA")
        )])
        store.receive(GatewayEventFrame(event: .chat(ChatEvent(
            runId: "runA", sessionKey: store.sessionKey, seq: 2,
            state: .delta(.init(deltaText: " continued"))))))

        #expect(store.messages.count == 1)
        #expect(store.messages[0].id == "entryA")
        #expect(store.messages[0].text == "snapshot continued")
        #expect(store.messages[0].isStreaming)
    }

    @Test @MainActor func fakeGatewayStreamsReply() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.streamChatReply("hello from the fake")
        let url = try await fake.start()
        defer { fake.stop() }

        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        let store = ConversationStore(connection: connection)
        await store.start()
        await store.send("hello")
        // A reconnect history pass may run before the canonical user row arrives.
        store.reconcileHistory([])
        #expect(store.messages.first?.text == "hello")

        for _ in 0..<30 where store.isStreaming {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.messages.map(\.text) == ["hello", "hello from the fake"])
        #expect(store.messages.map(\.role) == [.user, .assistant])
        #expect(!store.isStreaming)
        #expect(fake.receivedRequests.first(where: { $0.method == "chat.send" })?.params?["message"]?.stringValue == "hello")
        store.stopListening()
        await connection.disconnect()
    }

    @Test @MainActor func fakeGatewayAbortStopsCurrentRun() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.streamChatReply("delayed reply")
        let url = try await fake.start()
        defer { fake.stop() }

        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        let store = ConversationStore(connection: connection)
        await store.start()
        await store.send("stop this")
        await store.abort()

        for _ in 0..<20 where store.isStreaming {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!store.isStreaming)
        #expect(fake.receivedRequests.contains(where: { $0.method == "chat.abort" }))
        store.stopListening()
        await connection.disconnect()
    }

    @Test @MainActor func historyConfirmsOptimisticEchoWithoutDuplication() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.streamChatReply("reply")
        let url = try await fake.start()
        defer { fake.stop() }

        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        let store = ConversationStore(connection: connection)
        await store.start()
        await store.send("hello")
        let sendRequest = try #require(fake.receivedRequests.first(where: { $0.method == "chat.send" }))
        let key = try #require(sendRequest.params?["idempotencyKey"]?.stringValue)

        store.reconcileHistory([ChatMessage(role: .user, content: [.text("hello")],
                                             idempotencyKey: key, metadata: .init(id: "canonical-user"))])
        #expect(store.messages.filter { $0.role == .user }.count == 1)
        #expect(store.messages.first?.id == "canonical-user")
        let count = fake.receivedRequests.count
        await store.retry(idempotencyKey: key)
        #expect(fake.receivedRequests.count == count)
        store.stopListening()
        await connection.disconnect()
    }
}
