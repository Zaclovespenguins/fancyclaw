import Foundation
import GatewayProtocol
import TestSupport
import Testing

@Suite("Skill protocol")
struct SkillDecodingTests {
    @Test func sourceDerivedStatusFixtureDecodesAllIndependentFacts() throws {
        let result = try #require(Fixtures.decode(ResponseFrame<SkillsStatusResult>.self, from: "skills-status.res").payload)
        #expect(result.agentId == "main")
        #expect(result.skills.count == 6)
        let calendar = try #require(result.skills.first { $0.skillKey == "calendar" })
        #expect(calendar.eligible == true)
        #expect(calendar.disabled == false)
        #expect(calendar.blockedByAgentFilter == true)
        let notes = try #require(result.skills.first { $0.skillKey == "obsidian" })
        #expect(notes.modelVisible == false)
        #expect(notes.userInvocable == true)
        #expect(notes.commandVisible == true)
        let browser = try #require(result.skills.first { $0.skillKey == "browser" })
        #expect(browser.missing?.anyBins == ["chromium", "google-chrome"])
    }

    @Test func unknownFieldsSourcesAndNullableOptionalsAreTolerated() throws {
        let data = Data(#"{"agentId":null,"agentSkillFilter":null,"futureReport":{"x":1},"skills":[{"name":"Future","description":"Future skill","skillKey":"future","source":"future-source","emoji":null,"disabled":null,"eligible":null,"blockedByAgentFilter":null,"modelVisible":null,"requirements":{"bins":null,"anyBins":["one","two"],"futureRequirement":true},"missing":null,"futureStatus":"queued"}]}"#.utf8)
        let result = try GatewayCoding.decoder().decode(SkillsStatusResult.self, from: data)
        let skill = try #require(result.skills.first)
        #expect(result.agentId == nil)
        #expect(skill.source == "future-source")
        #expect(skill.emoji == nil)
        #expect(skill.eligible == nil)
        #expect(skill.requirements?.bins == nil)
        #expect(skill.requirements?.anyBins == ["one", "two"])
        #expect(skill.missing == nil)
        // Optional open source metadata may itself be null.
        let nullSource = Data(#"{"name":"Null","description":"","skillKey":"null","source":null}"#.utf8)
        #expect(try GatewayCoding.decoder().decode(SkillStatus.self, from: nullSource).source == nil)
    }

    @Test func requestParamsAreStrictWithAllOptionalsAndOmitAbsentValues() throws {
        let schema = try Fixtures.schema()
        let full = try JSONValue(encoding: SkillsStatusParams(agentId: "main", sessionKey: "agent:main:main"))
        #expect(schema.violations(of: full, against: "SkillsStatusParams") == [])
        #expect(full == .object(["agentId": .string("main"), "sessionKey": .string("agent:main:main")]))
        let empty = try JSONValue(encoding: SkillsStatusParams())
        #expect(empty == .object([:]))
        #expect(schema.violations(of: empty, against: "SkillsStatusParams") == [])
        #expect(!schema.violations(of: .object(["agentId": .string("")]), against: "SkillsStatusParams").isEmpty)
        #expect(!schema.violations(of: .object(["toggle": .bool(true)]), against: "SkillsStatusParams").isEmpty)
    }

    @Test func distinctNamesRemainDistinctWhenTheyShareConfigurationKey() throws {
        let payload = Data(#"{"skills":[{"name":"One","description":"","skillKey":"shared"},{"name":"Two","description":"","skillKey":"shared"}]}"#.utf8)
        let result = try GatewayCoding.decoder().decode(SkillsStatusResult.self, from: payload)
        #expect(result.skills.map(\.id) == ["One", "Two"])
        #expect(result.skills.map(\.skillKey) == ["shared", "shared"])
    }
}
