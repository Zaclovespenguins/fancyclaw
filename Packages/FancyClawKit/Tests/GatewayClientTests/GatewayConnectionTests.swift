import Foundation
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing

@Suite("Gateway handshake", .serialized)
struct GatewayConnectionTests {
    @Test(.timeLimit(.minutes(1)))
    func messageChangeDoesNotInterruptHistoryOrLaterChatEvents() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.enableSessions()
        let messages = [ChatMessage(role: .assistant, content: [.text("Reply")])]
        fake.seedHistory(messages, sessionKey: "agent:main:main")
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        let stream = await connection.events()
        let received = Task {
            var events: [GatewayEventFrame] = []
            for await event in stream {
                events.append(event)
                if events.count == 2 { break }
            }
            return events
        }
        defer { received.cancel() }

        // Send wire JSON, not a re-encoded SessionsChanged, to reproduce the missing reason.
        fake.emitWireFrame(try Fixtures.frame("sessions-changed-message.event"))
        let history = try await connection.request("chat.history",
            params: ChatHistoryParams(sessionKey: "agent:main:main"), returning: ChatHistoryPage.self,
            timeout: .seconds(3))
        #expect(history.messages == messages)
        fake.emitWireFrame(try Fixtures.frame("chat-final.event"))
        // A second RPC is a bounded barrier after the final event on the same socket.
        let laterHistory = try await connection.request("chat.history",
            params: ChatHistoryParams(sessionKey: "agent:main:main"), returning: ChatHistoryPage.self,
            timeout: .seconds(3))
        #expect(laterHistory.messages == messages)
        let events = await received.value
        #expect(events.map { $0.event.name } == ["sessions.changed", "chat"])
        #expect(events.last?.seq == 103)
        #expect(fake.receivedConnects.count == 1)
        #expect(fake.recordedFailures.isEmpty)
        await connection.disconnect()
    }

    @Test func happyPath() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        let response = try await connection.connect(to: url, token: "test-token")
        #expect(response.server.connId == hello.server.connId)
        #expect(fake.recordedFailures.isEmpty)
        #expect(fake.receivedConnects.first?.client.id == .iOSApp)
        await connection.disconnect()
    }

    @Test(arguments: ["error-pairing-required.res", "error-auth-token-mismatch.res"])
    func authFailure(fixture: String) async throws {
        let expected = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: fixture).error)
        let fake = FakeGateway(replies: [.failure(expected)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        do {
            _ = try await connection.connect(to: url, token: "test-token")
            Issue.record("Expected the Gateway error")
        } catch let error as GatewayErrorShape {
            #expect(error.detailCode == expected.detailCode)
        }
    }

    @Test func startupRetry() async throws {
        let failure = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "error-startup-unavailable.res").error)
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.failure(failure), .hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        #expect(fake.receivedConnects.count == 2)
        await connection.disconnect()
    }

    @Test func oversizedConnectIsNeverSent() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        do {
            _ = try await connection.connect(to: url, token: String(repeating: "x", count: 70_000))
            Issue.record("Expected the pre-auth size limit")
        } catch ConnectionError.frameTooLarge {
            #expect(fake.receivedConnects.isEmpty)
        }
    }

    @Test func correlatesConcurrentRequests() async throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.reply(to: "first", with: .string("one"))
        fake.reply(to: "second", with: .string("two"))
        let url = try await fake.start()
        defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        async let first: JSONValue = connection.request("first", params: Optional<JSONValue>.none,
                                                        returning: JSONValue.self)
        async let second: JSONValue = connection.request("second", params: Optional<JSONValue>.none,
                                                         returning: JSONValue.self)
        let values = try await (first, second)
        #expect(values.0 == .string("one"))
        #expect(values.1 == .string("two"))
        await connection.disconnect()
    }
}
