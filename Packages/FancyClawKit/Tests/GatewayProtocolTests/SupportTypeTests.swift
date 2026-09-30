import Foundation
import GatewayProtocol
import Testing
import TestSupport

@Suite("JSONValue")
struct JSONValueTests {
    @Test func decodesEveryKind() throws {
        let value = try decode(JSONValue.self, #"{"a":null,"b":true,"c":3,"d":1.5,"e":"x","f":[1,"y"],"g":{"h":false}}"#)
        #expect(value == ["a": nil, "b": true, "c": 3, "d": 1.5, "e": "x", "f": [1, "y"], "g": ["h": false]])
    }

    @Test func largeMillisecondTimestampsStayIntegers() throws {
        #expect(try decode(JSONValue.self, "1737264000000") == .integer(1_737_264_000_000))
    }

    @Test func decodesAsConcreteType() throws {
        let value: JSONValue = ["nonce": "n", "ts": 5]
        #expect(try value.decode(as: ConnectChallenge.self) == ConnectChallenge(nonce: "n", ts: 5))
    }

    @Test func accessors() {
        let value: JSONValue = ["count": 2, "ratio": 2.0, "name": "x", "flag": true]
        #expect(value["count"]?.intValue == 2)
        #expect(value["ratio"]?.intValue == 2)
        #expect(value["name"]?.stringValue == "x")
        #expect(value["flag"]?.boolValue == true)
        #expect(value["missing"] == nil)
        #expect(JSONValue.string("x")["key"] == nil)
    }
}

@Suite("OpenEnum")
struct OpenEnumTests {
    @Test(arguments: OperatorScope.knownCases)
    func knownScopesRoundTrip(scope: OperatorScope) throws {
        #expect(OperatorScope(rawValue: scope.rawValue) == scope)
        #expect(try decode(OperatorScope.self, "\"\(scope.rawValue)\"") == scope)
    }

    @Test func unknownValuesRoundTrip() throws {
        let scope = try decode(OperatorScope.self, #""operator.teleport""#)
        #expect(scope == .unknown("operator.teleport"))
        #expect(!scope.isKnown)
        #expect(try JSONValue(encoding: scope) == "operator.teleport")
    }

    @Test func rawValuesAreUnique() {
        func check<E: OpenEnum>(_: E.Type) {
            let raw = E.knownCases.map(\.rawValue)
            #expect(Set(raw).count == raw.count, "\(E.self) has duplicate raw values")
        }
        check(GatewayErrorCode.self)
        check(GatewayErrorDetailCode.self)
        check(ConnectRecoveryStep.self)
        check(GatewayRole.self)
        check(OperatorScope.self)
        check(ClientCapability.self)
        check(AuthMethod.self)
        check(ChatRole.self)
        check(ChatRunPhase.self)
        check(ChatErrorKind.self)
        check(ChatSendStatus.self)
        check(SessionKind.self)
        check(SessionRunStatus.self)
        check(ApprovalDecision.self)
        check(FrameType.self)
    }
}

@Suite("Schema checker")
struct ProtocolSchemaTests {
    let schema: ProtocolSchema

    init() throws {
        schema = try Fixtures.schema()
    }

    @Test func flagsExtraKeysInClosedObjects() {
        let violations = schema.violations(of: ["sessionKey": "s", "surprise": 1], against: "ChatAbortParams")
        #expect(violations == ["$: unexpected key surprise in a closed object"])
    }

    @Test func flagsMissingRequiredKeys() {
        #expect(schema.violations(of: [:], against: "ChatAbortParams") == ["$: missing required key sessionKey"])
    }

    @Test func flagsValuesOutsideEnums() {
        let frame: JSONValue = [
            "minProtocol": 4, "maxProtocol": 4,
            "client": ["id": "fancyclaw", "version": "1", "platform": "ios", "mode": "ui"],
        ]
        #expect(schema.violations(of: frame, against: "ConnectParams").count == 1)
    }

    @Test func flagsUnmatchedUnionBranches() {
        let event: JSONValue = ["runId": "r", "sessionKey": "s", "seq": 1, "state": "later"]
        #expect(!schema.violations(of: event, against: "ChatEvent").isEmpty)
    }

    @Test func subsetComparison() {
        let full: JSONValue = ["a": 1, "b": ["c": [1, 2]], "d": "x"]
        let sameValues: JSONValue = ["a": 1.0, "b": ["c": [1, 2]]]
        let changedValue: JSONValue = ["a": 2]
        let extraKey: JSONValue = ["z": 1]
        let shorterArray: JSONValue = ["b": ["c": [1]]]
        #expect(sameValues.isJSONSubset(of: full))
        #expect(!changedValue.isJSONSubset(of: full))
        #expect(!extraKey.isJSONSubset(of: full))
        #expect(!shorterArray.isJSONSubset(of: full))
    }
}
