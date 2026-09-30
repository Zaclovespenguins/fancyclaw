import Foundation
import GatewayProtocol
import Testing
import TestSupport

/// Every bundled frame fixture, with the Swift type it decodes as and the schema definitions it must satisfy.
struct FixtureCase: Sendable, CustomTestStringConvertible {
    enum Direction: Sendable {
        /// Sent by FancyClaw: re-encoding must reproduce the fixture exactly.
        case outbound
        /// Sent by the Gateway: re-encoding may drop unmodeled fields but must not add or change any.
        case inbound
    }

    let name: String
    let direction: Direction
    let frameDefinition: String
    /// The definition for the frame's `params` or `payload`, when the schema has one.
    let bodyDefinition: String?
    let bodyKey: String
    let reencode: @Sendable (Data) throws -> JSONValue

    var testDescription: String { name }

    static func request<Params: Codable & Sendable>(
        _ name: String, _: Params.Type, body: String?
    ) -> FixtureCase {
        FixtureCase(
            name: name, direction: .outbound, frameDefinition: "RequestFrame", bodyDefinition: body,
            bodyKey: "params",
            reencode: { try JSONValue(encoding: GatewayCoding.decoder().decode(RequestFrame<Params>.self, from: $0)) })
    }

    static func response<Payload: Codable & Sendable>(
        _ name: String, _: Payload.Type, body: String? = nil
    ) -> FixtureCase {
        FixtureCase(
            name: name, direction: .inbound, frameDefinition: "ResponseFrame", bodyDefinition: body,
            bodyKey: "payload",
            reencode: { try JSONValue(encoding: GatewayCoding.decoder().decode(ResponseFrame<Payload>.self, from: $0)) })
    }

    static func event(_ name: String, body: String? = nil) -> FixtureCase {
        FixtureCase(
            name: name, direction: .inbound, frameDefinition: "EventFrame", bodyDefinition: body,
            bodyKey: "payload",
            reencode: { try JSONValue(encoding: GatewayCoding.decoder().decode(GatewayEventFrame.self, from: $0)) })
    }

    static let all: [FixtureCase] = [
        // Handshake
        .event("connect-challenge.event"),
        .request("connect.req", ConnectParams.self, body: "ConnectParams"),
        .request("connect-bootstrap.req", ConnectParams.self, body: "ConnectParams"),
        .response("hello-ok.res", HelloOK.self, body: "HelloOk"),
        .response("hello-ok-bootstrap.res", HelloOK.self, body: "HelloOk"),
        .response("error-pairing-required.res", JSONValue.self),
        .response("error-auth-token-mismatch.res", JSONValue.self),
        .response("error-startup-unavailable.res", JSONValue.self),
        .response("error-missing-scope.res", JSONValue.self),
        .response("error-approval-not-found.res", JSONValue.self),
        .response("error-future-code.res", JSONValue.self),
        // Chat
        .request("chat-send-attachment.req", ChatSendParams.self, body: "ChatSendParams"),
        .request("chat-send.req", ChatSendParams.self, body: "ChatSendParams"),
        .response("chat-send.res", ChatSendResponse.self),
        .response("chat-send-in-flight.res", ChatSendResponse.self),
        .request("chat-abort.req", ChatAbortParams.self, body: "ChatAbortParams"),
        .request("chat-history.req", ChatHistoryParams.self, body: "ChatHistoryParams"),
        .request("chat-history-catch-up.req", ChatHistoryParams.self, body: "ChatHistoryParams"),
        .response("chat-history.res", ChatHistoryPage.self),
        .response("chat-history-delta.res", ChatHistoryCatchUp.self, body: "ChatHistoryCursorResult"),
        .response("chat-history-reset.res", ChatHistoryCatchUp.self, body: "ChatHistoryCursorResult"),
        .event("chat-status.event", body: "ChatEvent"),
        .event("chat-delta.event", body: "ChatEvent"),
        .event("chat-delta-replace.event", body: "ChatEvent"),
        .event("chat-final.event", body: "ChatEvent"),
        .event("chat-aborted.event", body: "ChatEvent"),
        .event("chat-error.event", body: "ChatEvent"),
        .event("chat-error-unclassified.event", body: "ChatEvent"),
        // Liveness
        .event("tick.event", body: "TickEvent"),
        .event("shutdown.event", body: "ShutdownEvent"),
        // Sessions
        .request("sessions-list.req", SessionsListParams.self, body: "SessionsListParams"),
        .response("sessions-list.res", SessionsListResult.self),
        // Approvals
        .event("exec-approval-requested.event"),
        .event("exec-approval-resolved.event"),
        .request("exec-approval-resolve.req", ExecApprovalResolveParams.self, body: "ExecApprovalResolveParams"),
        .response("exec-approval-resolve.res", JSONValue.self),
        // Events FancyClaw doesn't model yet
        .event("agent-tool.event"),
        .event("future.event"),
        .event("no-payload.event"),
    ]
}
