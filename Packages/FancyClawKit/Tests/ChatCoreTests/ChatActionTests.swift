import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing

@Suite("Shortcut chat actions")
struct ChatActionTests {
    private func gateway() throws -> FakeGateway {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        return FakeGateway(replies: [.hello(hello)])
    }

    @Test @MainActor func askUsesTheOutboxAndReturnsFinalText() async throws {
        let fake = try gateway()
        fake.streamChatReply("Final reply")
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection)
        await store.start()
        #expect(try await store.ask("Question") == "Final reply")
        let request = try #require(fake.receivedRequests.first { $0.method == "chat.send" })
        #expect(request.params?["message"]?.stringValue == "Question")
        #expect(request.params?["sessionKey"]?.stringValue == SessionKey.main.rawValue)
        #expect(request.params?["idempotencyKey"]?.stringValue?.isEmpty == false)
        store.stopListening()
        await connection.disconnect()
    }

    @Test @MainActor func askAdoptsServerRunIDAndIgnoresOtherRuns() async throws {
        let fake = try gateway()
        fake.reply(to: "chat.send", with: try JSONValue(encoding: ChatSendResponse(runId: "server-run", status: .started)))
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection)
        await store.start()
        let result = Task { try await store.ask("Question") }
        for _ in 0..<100 where !fake.receivedRequests.contains(where: { $0.method == "chat.send" }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fake.receivedRequests.contains(where: { $0.method == "chat.send" }))
        fake.emit(.init(event: .chat(.init(runId: "wrong", sessionKey: store.sessionKey, seq: 1,
            state: .final(.init(message: .init(role: .assistant, content: [.text("Wrong reply")])))))))
        fake.emit(.init(event: .chat(.init(runId: "server-run", sessionKey: "other-session", seq: 1,
            state: .final(.init(message: .init(role: .assistant, content: [.text("Wrong session")])))))))
        fake.emit(.init(event: .chat(.init(runId: "server-run", sessionKey: store.sessionKey, seq: 1,
            state: .delta(.init(deltaText: "Old"))))))
        fake.emit(.init(event: .chat(.init(runId: "server-run", sessionKey: store.sessionKey, seq: 2,
            state: .final(.init(message: .init(role: .assistant, content: [.text("Yielded reply")]), yielded: true))))))
        fake.emit(.init(event: .chat(.init(runId: "server-run", sessionKey: store.sessionKey, seq: 3,
            state: .delta(.init(deltaText: "Replacement", replace: true))))))
        fake.emit(.init(event: .chat(.init(runId: "server-run", sessionKey: store.sessionKey, seq: 4, state: .final(.init())))))
        #expect(try await result.value == "Replacement")
        store.stopListening()
        await connection.disconnect()
    }

    @Test @MainActor func boundedWaitKeepsTheRemoteRunAndOutbox() async throws {
        let fake = try gateway()
        fake.reply(to: "chat.send", with: try JSONValue(encoding: ChatSendResponse(runId: "slow", status: .started)))
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection)
        let immediate = GatewayTiming(now: { .zero }, sleep: { _ in })
        let reply = try await store.ask("Slow question", timing: immediate)
        #expect(reply.contains("Your message was sent"))
        #expect(store.isStreaming)
        #expect(store.messages.contains { $0.role == .user && $0.text == "Slow question" })
        #expect(!fake.receivedRequests.contains { $0.method == "chat.abort" })
        await connection.disconnect()
    }

    @Test @MainActor func sendFailureIsAnErrorInsteadOfASuccessDialog() async throws {
        let fake = try gateway()
        fake.fail("chat.send", with: .init(code: .forbidden, message: "Denied"))
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: fake.start(), token: "test-token")
        let store = ConversationStore(connection: connection)
        await #expect(throws: ChatActionError.self) { try await store.ask("Question") }
        #expect(store.errorMessage != nil)
        await connection.disconnect()
    }

    @Test @MainActor func emptyBusyAndInvalidatedChatsDoNotSend() async {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        await #expect(throws: ChatActionError.self) { try await store.ask(" \n") }
        store.receive(.init(event: .chat(.init(runId: "busy", sessionKey: store.sessionKey, seq: 1, state: .status(.init(phase: nil))))))
        await #expect(throws: ChatActionError.self) { try await store.ask("Question") }
        store.invalidate()
        await #expect(throws: ChatActionError.self) { try await store.ask("Question") }
        #expect(store.messages.isEmpty)
    }
}
