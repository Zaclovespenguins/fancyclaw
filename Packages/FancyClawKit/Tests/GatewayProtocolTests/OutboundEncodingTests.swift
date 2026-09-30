import Foundation
import GatewayProtocol
import Testing
import TestSupport

/// The Gateway rejects unknown fields in closed schemas, so every request FancyClaw builds is checked against
/// the official definitions with every optional field populated.
@Suite("Outbound encoding")
struct OutboundEncodingTests {
    let schema: ProtocolSchema

    init() throws {
        schema = try Fixtures.schema()
    }

    private func violations(of value: some Codable & Sendable, method: String, definition: String) throws -> [String] {
        let frame = try JSONValue(encoding: RequestFrame(id: "req-1", method: method, params: value))
        let params = try #require(frame["params"])
        return schema.violations(of: frame, against: "RequestFrame")
            + schema.violations(of: params, against: definition)
    }

    @Test func connectParams() throws {
        let params = ConnectParams(
            client: ClientInfo(
                id: .iOSApp, displayName: "FancyClaw", version: "1.0.0", platform: "ios", deviceFamily: "iPhone",
                modelIdentifier: "iPhone18,1", timeZone: "America/Denver", mode: .ui, instanceId: "instance-1"),
            role: .operator, scopes: [.read, .write, .approvals],
            caps: [.toolEvents, .sessionScopedEvents, .approvals, .execApprovals, .pluginApprovals],
            auth: ConnectAuth(
                token: "fake-token", bootstrapToken: "fake-bootstrap", deviceToken: "fake-device", password: "fake-password"),
            locale: "en-US", userAgent: "FancyClaw/1.0.0",
            device: DeviceProof(id: "00", publicKey: "AA", signature: "AA", signedAt: 1, nonce: "fake-nonce"))
        #expect(try violations(of: params, method: "connect", definition: "ConnectParams") == [])
    }

    @Test func chatSendParams() throws {
        let params = ChatSendParams(
            sessionKey: "agent:main:main", message: "Hello", idempotencyKey: "key-1",
            attachments: [ChatAttachment(
                type: "image", mimeType: "image/jpeg", fileName: "a.jpg", origin: .paste, content: "AAAA",
                sizeBytes: 3, width: 1, height: 1, durationMs: 0)],
            thinking: "high", queueMode: .steer)
        #expect(try violations(of: params, method: "chat.send", definition: "ChatSendParams") == [])
    }

    @Test func chatHistoryParams() throws {
        let params = ChatHistoryParams(sessionKey: "agent:main:main", cursor: "cursor", limit: 50, offset: 10)
        #expect(try violations(of: params, method: "chat.history", definition: "ChatHistoryParams") == [])
    }

    @Test func chatAbortParams() throws {
        let params = ChatAbortParams(sessionKey: "agent:main:main", runId: "run-1")
        #expect(try violations(of: params, method: "chat.abort", definition: "ChatAbortParams") == [])
    }

    @Test func sessionsListParams() throws {
        let params = SessionsListParams.drawer(limit: 20, offset: 40, search: "disk")
        #expect(try violations(of: params, method: "sessions.list", definition: "SessionsListParams") == [])
    }

    @Test func execApprovalResolveParams() throws {
        let params = ExecApprovalResolveParams(id: "approval-1", decision: .allowAlways)
        #expect(try violations(of: params, method: "exec.approval.resolve", definition: "ExecApprovalResolveParams") == [])
    }

    @Test func nilOptionalsAreOmitted() throws {
        let params = try JSONValue(encoding: ChatAbortParams(sessionKey: "agent:main:main"))
        #expect(params == ["sessionKey": "agent:main:main"])
    }

    @Test func requestWithoutParamsOmitsKey() throws {
        let frame = try JSONValue(encoding: RequestFrame<JSONValue>(id: "req-1", method: "health", params: nil))
        #expect(frame == ["type": "req", "id": "req-1", "method": "health"])
    }

    @Test func advertisedClientIdentityIsAcceptedBySchema() throws {
        let clientSchema = try #require(schema.definition("ConnectParams")?["properties"]?["client"]?["properties"])
        let ids = try #require(clientSchema["id"]?["enum"]?.arrayValue).compactMap { $0.stringValue }
        let modes = try #require(clientSchema["mode"]?["enum"]?.arrayValue).compactMap { $0.stringValue }
        #expect(Set(ids) == Set(GatewayClientID.allCases.map(\.rawValue)))
        #expect(Set(modes) == Set(GatewayClientMode.allCases.map(\.rawValue)))
    }
}

@Suite("Session requests match pinned schema")
struct SessionRequestEncodingTests {
    @Test func sessionMutationsAndCatalogs() throws {
        let schema = try Fixtures.schema()
        let cases: [(JSONValue, String)] = [
            (try JSONValue(encoding: SessionsCreateParams(agentId: "main", idempotencyKey: "new-key")), "SessionsCreateParams"),
            (try JSONValue(encoding: SessionsPatchParams(key: "s", label: "Title", model: "provider/model", archived: true, expectedSessionId: "id")), "SessionsPatchParams"),
            (try JSONValue(encoding: SessionKeyParams(key: "s", expectedSessionId: "id")), "SessionsResetParams"),
            (try JSONValue(encoding: SessionsDeleteParams(key: "s", expectedSessionId: "id")), "SessionsDeleteParams"),
            (try JSONValue(encoding: ModelsListParams()), "ModelsListParams")
        ]
        for (params, definition) in cases { #expect(schema.violations(of: params, against: definition).isEmpty) }
        #expect(try JSONValue(encoding: SessionsCreateParams(idempotencyKey: "key")) == ["idempotencyKey": "key"])
        #expect(try JSONValue(encoding: SessionsPatchParams(key: "s", label: "Title")) == ["key": "s", "label": "Title"])
    }

    @Test func changedEventDecodesMissingKeyAndFutureReason() throws {
        let value: JSONValue = ["type": "event", "event": "sessions.changed", "payload": ["reason": "future", "ts": 1]]
        let frame = try value.decode(as: GatewayEventFrame.self)
        guard case .sessionsChanged(let changed) = frame.event else { Issue.record("Expected session change"); return }
        #expect(changed.sessionKey == nil)
        #expect(changed.reason == "future")
    }
}
