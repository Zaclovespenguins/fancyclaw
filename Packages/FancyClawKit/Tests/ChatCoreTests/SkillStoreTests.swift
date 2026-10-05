import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing

@Suite("Skill store", .serialized) @MainActor
struct SkillStoreTests {
    private func hello() throws -> HelloOK {
        try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
        try #require(condition())
    }

    @Test func loadsSortsAndSearchesInstalledMetadataWithoutMutationRPCs() async throws {
        let fake = FakeGateway(replies: [.hello(try hello())])
        fake.reply(to: "skills.status", with: try SkillsDemo.payload())
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        await store.refresh()
        #expect(store.hasLoaded && !store.isLoading && !store.isStale)
        #expect(store.errorMessage == nil)
        #expect(store.agentID == "main")
        #expect(store.skills.map(\.name) == ["Browser", "Calendar", "GitHub", "Gmail", "Obsidian", "Weather"])
        store.search = "  PULL requests "
        #expect(store.visibleSkills.map(\.name) == ["GitHub"])
        store.search = "OBSIDIAN"
        #expect(store.visibleSkills.map(\.name) == ["Obsidian"])
        store.search = "no match"
        #expect(store.visibleSkills.isEmpty)
        #expect(fake.receivedRequests.map(\.method) == ["skills.status"])
        #expect(fake.receivedRequests.first?.params == .object([:]))
        await connection.disconnect()
    }

    @Test func readinessRestrictionsAndPromptVisibilityAreIndependent() throws {
        let result = try #require(Fixtures.decode(ResponseFrame<SkillsStatusResult>.self, from: "skills-status.res").payload)
        let statuses = Dictionary(uniqueKeysWithValues: result.skills.map { ($0.skillKey, $0.availability.label) })
        #expect(statuses["github"] == "Ready")
        #expect(statuses["gmail"] == "Off")
        #expect(statuses["browser"] == "Missing requirements")
        #expect(statuses["calendar"] == "Not selected for agent")
        #expect(statuses["weather"] == "Restricted")
        #expect(statuses["obsidian"] == "Ready") // Prompt-hidden, still eligible and command-visible.
        #expect(SkillStatus(name: "Unknown", description: "", skillKey: "unknown").availability.label == "Status unavailable")
    }

    @Test func failedRefreshKeepsSnapshotAndRecoveryClearsError() async throws {
        let fake = FakeGateway(replies: [.hello(try hello())])
        fake.reply(to: "skills.status", withSequence: [try SkillsDemo.payload()])
        fake.reply(to: "skills.status", with: .object(["skills": .null])) // Malformed required collection.
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        await store.refresh()
        await store.refresh()
        #expect(store.skills.count == 6 && store.isStale && !store.isLoading)
        #expect(store.errorMessage != nil)
        fake.reply(to: "skills.status", with: .object(["skills": .array([])]))
        await store.refresh()
        #expect(store.skills.isEmpty && store.hasLoaded && !store.isStale)
        #expect(store.errorMessage == nil)
        await connection.disconnect()
    }

    @Test func gatewayErrorAndOmittedReadScopeAreReportedTruthfully() async throws {
        var noRead = try hello(); noRead.auth.scopes = [.approvals]
        let fake = FakeGateway(replies: [.hello(noRead), .hello(try hello())])
        fake.fail("skills.status", with: .init(code: .forbidden, message: "Skills are forbidden"))
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        await store.refresh()
        #expect(store.errorMessage?.contains("permission to access skills") == true)
        #expect(fake.receivedRequests.isEmpty)
        await connection.disconnect()
        _ = try await connection.connect(to: url, token: "test")
        await store.refresh()
        #expect(store.errorMessage?.contains("Skills are forbidden") == true)
        #expect(!store.hasLoaded && !store.isLoading)
        await connection.disconnect()
    }

    @Test func writeOnlyGrantCanLoadSkills() async throws {
        var writeOnly = try hello(); writeOnly.auth.scopes = [.write]
        let fake = FakeGateway(replies: [.hello(writeOnly)])
        fake.reply(to: "skills.status", with: try SkillsDemo.payload())
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        await store.refresh()
        #expect(store.hasLoaded && !store.isStale && store.errorMessage == nil)
        #expect(store.skills.count == 6)
        #expect(fake.receivedRequests.map(\.method) == ["skills.status"])
        await connection.disconnect()
    }

    @Test func adminOnlyGrantCanLoadSkills() async throws {
        var adminOnly = try hello(); adminOnly.auth.scopes = [.admin]
        let fake = FakeGateway(replies: [.hello(adminOnly)])
        fake.reply(to: "skills.status", with: try SkillsDemo.payload())
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        await store.refresh()
        #expect(store.hasLoaded && !store.isStale && store.errorMessage == nil)
        #expect(store.skills.count == 6)
        #expect(fake.receivedRequests.map(\.method) == ["skills.status"])
        await connection.disconnect()
    }

    @Test func coalescedWaitersReturnOnlyAfterSnapshotPublication() async throws {
        let fake = FakeGateway(replies: [.hello(try hello())])
        fake.reply(to: "skills.status", with: try SkillsDemo.payload())
        fake.pauseResponses(to: "skills.status")
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        var firstFinished = false
        var secondStarted = false
        var secondFinished = false
        let first = Task { await store.refresh(); firstFinished = true }
        try await waitUntil { fake.receivedRequests.count == 1 }
        let second = Task { secondStarted = true; await store.refresh(); secondFinished = true }
        try await waitUntil { secondStarted }
        #expect(!firstFinished && !secondFinished && store.isLoading && !store.hasLoaded)
        #expect(fake.receivedRequests.count == 1)
        fake.resumeResponses(to: "skills.status")
        await first.value; await second.value
        #expect(firstFinished && secondFinished && store.hasLoaded && !store.isLoading)
        #expect(store.skills.count == 6 && store.agentID == "main")
        #expect(fake.receivedRequests.count == 1)
        await connection.disconnect()
    }

    @Test func inFlightRequestsCoalesceAndExternalCancellationDoesNotPublishError() async throws {
        let fake = FakeGateway(replies: [.hello(try hello())])
        // Unhandled fake methods remain pending, providing a deterministic cancellation boundary.
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        let first = Task { await store.refresh() }
        try await waitUntil { fake.receivedRequests.count == 1 }
        var secondStarted = false
        let second = Task { secondStarted = true; await store.refresh() }
        try await waitUntil { secondStarted }
        #expect(store.isLoading)
        first.cancel()
        await first.value; await second.value
        #expect(fake.receivedRequests.count == 1)
        #expect(!store.isLoading && !store.hasLoaded && store.errorMessage == nil)
        fake.reply(to: "skills.status", with: try SkillsDemo.payload())
        await store.refresh()
        #expect(store.skills.count == 6)
        await connection.disconnect()
    }

    @Test func disconnectRejectsOldResponseAndReconnectRefreshesSnapshot() async throws {
        let fake = FakeGateway(replies: [.hello(try hello()), .hello(try hello())])
        fake.reply(to: "skills.status", withSequence: [try SkillsDemo.payload()])
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        await store.refresh()
        let pending = Task { await store.refresh() }
        try await waitUntil { fake.receivedRequests.count == 2 }
        let request = try #require(fake.receivedRequests.last)
        store.connectionDidDisconnect()
        fake.emitWireFrame(ResponseFrame(id: request.id, ok: true, payload: JSONValue.object(["skills": .array([])])))
        await pending.value
        #expect(store.skills.count == 6 && store.isStale && store.errorMessage == nil)
        await connection.disconnect()
        fake.reply(to: "skills.status", with: .object(["agentId": .string("helper"), "skills": .array([])]))
        _ = try await connection.connect(to: url, token: "test")
        await store.refresh()
        #expect(store.agentID == "helper" && store.skills.isEmpty && !store.isStale)
        #expect(fake.receivedRequests.filter { $0.method == "skills.status" }.count == 3)
        await connection.disconnect()
    }

    @Test func explicitClearRejectsPendingResultAndRemovesProfileSnapshot() async throws {
        let fake = FakeGateway(replies: [.hello(try hello())])
        fake.reply(to: "skills.status", withSequence: [try SkillsDemo.payload()])
        let url = try await fake.start(); defer { fake.stop() }
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let store = SkillStore(connection: connection)
        await store.refresh()
        store.search = "Gmail"
        let pending = Task { await store.refresh() }
        try await waitUntil { fake.receivedRequests.count == 2 }
        store.clear()
        await pending.value
        #expect(store.skills.isEmpty && store.agentID == nil && store.search.isEmpty)
        #expect(!store.hasLoaded && !store.isStale && !store.isLoading && store.errorMessage == nil)
        await connection.disconnect()
    }
}
