import Foundation
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing
@testable import ChatCore

@Suite("Live delivery contract", .serialized) @MainActor
struct LiveDeliveryTests {
    @Test func scopedEventsArriveAndSubscriptionRenewsAfterReconnect() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello), .hello(hello)])
        fake.enableSessions()
        fake.enforceMessageSubscriptions()
        fake.streamChatReply("OK")
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        let store = ConversationStore(connection: connection, streamingInterval: .zero)
        for turn in 1...2 {
            _ = try await connection.connect(to: url, token: "test")
            await store.start()
            await store.refreshHistory()
            await store.send("diagnostic \(turn)")
            for _ in 0..<80 {
                if !store.isStreaming { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            #expect(!store.isStreaming)
            #expect(store.messages.filter { $0.role == .assistant }.count == turn)
            let requests = fake.receivedRequests
            #expect(requests.filter { $0.method == "sessions.messages.subscribe" }.count == turn)
            await store.refreshHistory()
            #expect(store.messages.filter { $0.role == .user }.count == turn)
            await connection.disconnect()
            store.connectionDidDisconnect()
        }
        store.stopListening()
    }

    @Test func canonicalUserSuffixConfirmsOnlyItsOwnEcho() async throws {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        await store.send("same text")
        await store.send("same text")
        let firstID = try #require(store.messages.first?.id)
        let key = String(firstID.dropLast(":user".count))
        store.reconcileHistory([
            ChatMessage(role: .user, content: [.text("same text")], idempotencyKey: key + ":user", metadata: .init(id: "canonical"))
        ])
        #expect(store.messages.filter { $0.role == .user }.count == 2)
        #expect(store.messages.filter { $0.role == .user }.first?.id == "canonical")
        #expect(!store.messages.contains { $0.id == firstID })
    }

    @Test func assistantIdentityDoesNotConfirmAUserSend() async throws {
        let store = ConversationStore(connection: GatewayConnection(identity: .generate()))
        await store.send("pending")
        let id = try #require(store.messages.first?.id)
        let key = String(id.dropLast(":user".count))
        store.reconcileHistory([ChatMessage(role: .assistant, content: [.text("reply")], idempotencyKey: key)])
        #expect(store.messages.contains { $0.id == id && $0.deliveryFailed })
    }

    @Test func rejectedSubscriptionPreventsSendingWithoutEventRouting() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.fail("sessions.messages.subscribe", with: .init(code: .invalidRequest, message: "Subscription denied"))
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = ConversationStore(connection: connection)
        await store.send("diagnostic")
        #expect(store.messages.first?.deliveryFailed == true)
        #expect(!store.isStreaming)
        #expect(!fake.receivedRequests.contains { $0.method == "chat.send" })
        await connection.disconnect()
    }

}
