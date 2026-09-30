import Foundation
import GatewayProtocol
import Testing
import TestSupport

@Suite("Handshake decoding")
struct HandshakeDecodingTests {
    @Test func challenge() throws {
        let frame = try Fixtures.decode(GatewayEventFrame.self, from: "connect-challenge.event")
        #expect(frame.event == .connectChallenge(ConnectChallenge(nonce: "fake-nonce-0001", ts: 1_737_264_000_000)))
    }

    @Test func helloOK() throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        #expect(hello.protocol == ProtocolVersion.current)
        #expect(hello.server.connId == "conn-fake-0001")
        #expect(hello.auth.role == .operator)
        #expect(hello.auth.scopes == [.read, .write, .approvals])
        #expect(hello.auth.method == .deviceToken)
        #expect(hello.auth.deviceToken == "fake-device-token-0001")
        #expect(hello.policy.tickIntervalMs == 15_000)
        #expect(hello.policy.attachments == HelloOK.AttachmentLimits(maxBytes: 20_971_520, maxImageBytes: 6_291_456))
        #expect(hello.snapshot.sessionDefaults?.mainSessionKey == "agent:main:main")
        #expect(hello.features.events.contains(GatewayEvent.Name.chat))
    }

    @Test func bootstrapHelloCarriesOperatorToken() throws {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok-bootstrap.res").payload)
        #expect(hello.auth.role == .node)
        #expect(hello.policy.attachments == nil)
        let operatorToken = try #require(hello.auth.deviceTokens?.first { $0.role == .operator })
        #expect(operatorToken.deviceToken == "fake-operator-token-0000")
        #expect(operatorToken.scopes.contains(.talkSecrets))
    }

    @Test func rejectsPayloadThatIsNotHelloOK() {
        #expect(throws: DecodingError.self) {
            try decode(HelloOK.self, #"{"type":"hello-later","protocol":4}"#)
        }
    }

    @Test func pairingRequired() throws {
        let error = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "error-pairing-required.res").error)
        #expect(error.code == .notPaired)
        #expect(error.detailCode == .pairingRequired)
        #expect(error.pairingRequestId == "fake-pairing-request-0001")
        #expect(error.recommendedNextStep == .waitThenRetry)
    }

    @Test func authTokenMismatch() throws {
        let error = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "error-auth-token-mismatch.res").error)
        #expect(error.detailCode == .authTokenMismatch)
        #expect(error.canRetryWithDeviceToken)
        #expect(error.recommendedNextStep == .retryWithDeviceToken)
        #expect(error.pairingRequestId == nil)
    }

    @Test func startupUnavailable() throws {
        let error = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "error-startup-unavailable.res").error)
        #expect(error.isStartupUnavailable)
        #expect(error.retryable == true)
        #expect(error.retryAfterMs == 500)
    }

    @Test func missingScope() throws {
        let error = try #require(Fixtures.decode(ResponseFrame<JSONValue>.self, from: "error-missing-scope.res").error)
        #expect(error.code == .forbidden)
        #expect(error.missingScope == .approvals)
    }

    @Test func unknownErrorCodesAreTolerated() throws {
        let frame = try Fixtures.decode(ResponseFrame<JSONValue>.self, from: "error-future-code.res")
        #expect(frame.error?.code == .unknown("SOMETHING_NEW"))
        #expect(frame.error?.detailCode == .unknown("SOMETHING_NEWER"))
        #expect(frame.error?.code.isKnown == false)
    }

    @Test func failedResponseIgnoresPayload() throws {
        let frame = try decode(
            ResponseFrame<HelloOK>.self,
            #"{"type":"res","id":"1","ok":false,"payload":{"unexpected":true},"error":{"code":"UNAVAILABLE","message":"down"}}"#)
        #expect(frame.payload == nil)
        guard case .failure(let error) = frame.result else {
            Issue.record("Expected a failure result")
            return
        }
        #expect(error.code == .unavailable)
    }

    @Test func frameTypeIsChecked() {
        #expect(throws: DecodingError.self) {
            try decode(ResponseFrame<JSONValue>.self, #"{"type":"event","id":"1","ok":true}"#)
        }
    }

    @Test(arguments: [
        ("connect.req", FrameType.request, "req-connect-0001" as String?, nil as String?),
        ("hello-ok.res", .response, "req-connect-0001", nil),
        ("tick.event", .event, nil, "tick"),
    ])
    func frameHeader(name: String, type: FrameType, id: String?, event: String?) throws {
        let header = try Fixtures.decode(FrameHeader.self, from: name)
        #expect(header.type == type)
        #expect(header.id == id)
        #expect(header.event == event)
    }
}
