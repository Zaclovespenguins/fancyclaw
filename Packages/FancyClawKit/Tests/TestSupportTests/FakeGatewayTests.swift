import Foundation
import GatewayClient
import GatewayProtocol
import Testing
@testable import TestSupport

@Suite("FakeGateway robustness", .serialized)
struct FakeGatewayTests {
    private func connected(_ fake: FakeGateway) async throws -> GatewayConnection {
        let url = try await fake.start()
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test-token")
        return connection
    }

    private func makeFake() throws -> FakeGateway {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        return FakeGateway(replies: [.hello(hello)])
    }

    @Test(.timeLimit(.minutes(1)))
    func abortDoesNotLeaveAStrayDelta() async throws {
        let fake = try makeFake()
        fake.streamChatReply("Hello")
        let connection = try await connected(fake)
        defer { fake.stop() }
        let stream = await connection.events()
        let collected = Task {
            var states: [String] = []
            for await frame in stream {
                if case .chat(let chat) = frame.event {
                    switch chat.state {
                    case .delta: states.append("delta")
                    case .final: states.append("final")
                    case .aborted: states.append("aborted")
                    default: states.append("other")
                    }
                }
            }
            return states
        }
        _ = try await connection.request("chat.send",
            params: ChatSendParams(sessionKey: "agent:main:main", message: "hi", idempotencyKey: "run-1"),
            returning: ChatSendResponse.self, timeout: .seconds(3))
        _ = try await connection.request("chat.abort",
            params: ChatAbortParams(sessionKey: "agent:main:main", runId: "run-1"),
            returning: JSONValue.self, timeout: .seconds(3))
        try await Task.sleep(for: .milliseconds(400))
        collected.cancel()
        let states = await collected.value
        #expect(states == ["aborted"])
        await connection.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func stopBeforeReadyThrowsInsteadOfHanging() async throws {
        let fake = try makeFake()
        let start = Task { try await fake.start() }
        fake.stop()
        let outcome = await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await start.value) == nil }
            group.addTask { try? await Task.sleep(for: .seconds(1)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(outcome, "start() should throw promptly after stop() rather than hang")
    }

    @Test(.timeLimit(.minutes(1)))
    func normalStartAndStop() async throws {
        let fake = try makeFake()
        let url = try await fake.start()
        #expect(url.scheme == "ws")
        fake.stop()
        #expect(fake.recordedFailures.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedRequestDoesNotKillTheReceiveLoop() async throws {
        let fake = try makeFake()
        fake.enableSessions()
        let connection = try await connected(fake)
        defer { fake.stop() }
        // `id` must be a string, so the fake's typed decode throws.
        await #expect(throws: (any Error).self) {
            _ = try await connection.request("exec.approval.resolve", params: JSONValue.object(["id": .integer(5)]),
                returning: JSONValue.self, timeout: .seconds(2))
        }
        let list = try await connection.request("sessions.list", params: JSONValue.object([:]),
            returning: JSONValue.self, timeout: .seconds(2))
        #expect(list["sessions"] != nil)
        #expect(!fake.recordedFailures.isEmpty)
        await connection.disconnect()
    }
}

@Suite("Schema checker constraints")
struct ProtocolSchemaConstraintTests {
    let schema: ProtocolSchema

    init() throws { schema = try Fixtures.schema() }

    @Test func flagsValuesAboveMaximum() {
        #expect(!schema.violations(of: ["sessionKey": "k", "limit": 5000], against: "ChatHistoryParams").isEmpty)
        #expect(schema.violations(of: ["sessionKey": "k", "limit": 5], against: "ChatHistoryParams").isEmpty)
        #expect(!schema.violations(of: ["key": "k", "ttlMinutes": 121], against: "SessionsPatchParams").isEmpty)
        #expect(schema.violations(of: ["key": "k", "ttlMinutes": 120], against: "SessionsPatchParams").isEmpty)
    }

    @Test func flagsTooManyItems() {
        let mention: JSONValue = ["profileId": "p", "start": 0, "end": 1]
        let tooMany: JSONValue = ["sessionKey": "k", "message": "m", "idempotencyKey": "i",
                                  "mentions": .array(Array(repeating: mention, count: 11))]
        #expect(!schema.violations(of: tooMany, against: "ChatSendParams").isEmpty)
    }

    @Test func flagsMutuallyExclusiveModelsListKeys() {
        #expect(!schema.violations(of: ["sessionKey": "s", "authProfileId": "a"], against: "ModelsListParams").isEmpty)
        #expect(!schema.violations(of: ["preparedOnly": true, "refresh": true], against: "ModelsListParams").isEmpty)
        #expect(schema.violations(of: ["sessionKey": "s", "refresh": true], against: "ModelsListParams").isEmpty)
    }

    @Test func oneOfRequiresExactlyOneMatch() {
        let schema: JSONValue = ["oneOf": [["type": "integer"], ["type": "number"]]]
        #expect(!ProtocolSchema.violations(of: 1, against: schema, path: "$").isEmpty)
        #expect(ProtocolSchema.violations(of: 1.5, against: schema, path: "$").isEmpty)
    }

    @Test func anyOfAndOneOfAreCheckedIndependently() {
        let schema: JSONValue = ["anyOf": [["type": "string"]], "oneOf": [["type": "integer"]]]
        #expect(!ProtocolSchema.violations(of: 1, against: schema, path: "$").isEmpty)
        #expect(!ProtocolSchema.violations(of: "x", against: schema, path: "$").isEmpty)
    }

    @Test func checksPatternAndMinItems() {
        let pattern: JSONValue = ["type": "string", "pattern": "^[a-z]+$"]
        #expect(ProtocolSchema.violations(of: "abc", against: pattern, path: "$").isEmpty)
        #expect(!ProtocolSchema.violations(of: "ABC", against: pattern, path: "$").isEmpty)
        let items: JSONValue = ["type": "array", "minItems": 1, "maxItems": 2]
        #expect(!ProtocolSchema.violations(of: [], against: items, path: "$").isEmpty)
        #expect(!ProtocolSchema.violations(of: [1, 2, 3], against: items, path: "$").isEmpty)
    }
}
