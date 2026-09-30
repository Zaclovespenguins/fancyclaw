import Foundation
import GatewayProtocol
import Testing
import TestSupport

@Suite("Fixtures")
struct FixtureConformanceTests {
    @Test func schemaSubsetMatchesPinnedRelease() throws {
        #expect(try Fixtures.schema().release == ProtocolVersion.pinnedRelease)
    }

    @Test func everyFixtureIsCataloged() {
        #expect(Set(Fixtures.frameNames) == Set(FixtureCase.all.map(\.name)))
    }

    @Test("Fixture conforms to the official schema", arguments: FixtureCase.all)
    func conformsToSchema(_ fixture: FixtureCase) throws {
        let schema = try Fixtures.schema()
        let frame = try Fixtures.frame(fixture.name)
        #expect(schema.violations(of: frame, against: fixture.frameDefinition) == [])
        if let bodyDefinition = fixture.bodyDefinition {
            let body = try #require(frame[fixture.bodyKey])
            #expect(schema.violations(of: body, against: bodyDefinition) == [])
        }
    }

    @Test("Fixture round-trips through its model", arguments: FixtureCase.all)
    func roundTrips(_ fixture: FixtureCase) throws {
        let original = try Fixtures.frame(fixture.name)
        let reencoded = try fixture.reencode(Fixtures.frameData(fixture.name))
        switch fixture.direction {
        case .outbound:
            #expect(reencoded.jsonEquals(original))
        case .inbound:
            #expect(reencoded.isJSONSubset(of: original))
        }
    }

    @Test func missingScopeDetailsMatchSchema() throws {
        let details = try #require(Fixtures.frame("error-missing-scope.res")["error"]?["details"])
        #expect(try Fixtures.schema().violations(of: details, against: "MissingScopeErrorDetails") == [])
    }

    @Test func sessionRowsMatchSchema() throws {
        let schema = try Fixtures.schema()
        let rows = try #require(Fixtures.frame("sessions-list.res")["payload"]?["sessions"]?.arrayValue)
        for row in rows {
            #expect(schema.violations(of: row, against: "SessionRow") == [])
        }
    }
}
