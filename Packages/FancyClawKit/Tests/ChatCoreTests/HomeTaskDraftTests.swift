import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import TestSupport
import Testing

@Suite("Home task draft", .serialized, .timeLimit(.minutes(1))) @MainActor
struct HomeTaskDraftTests {
    private struct Failed: LocalizedError { var errorDescription: String? { "Task rejected" } }

    private func setup() async throws -> (FakeGateway, GatewayConnection, SessionStore) {
        let hello = try #require(Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload)
        let fake = FakeGateway(replies: [.hello(hello)])
        fake.enableSessions()
        let url = try await fake.start()
        let connection = GatewayConnection(identity: .generate())
        _ = try await connection.connect(to: url, token: "test")
        let sessions = SessionStore(connection: connection)
        await sessions.loadCatalogs()
        return (fake, connection, sessions)
    }

    @Test func defaultAgentAndGatewayDefaultModelIgnorePreviousChatSelection() async throws {
        let (fake, connection, sessions) = try await setup()
        defer { fake.stop() }
        sessions.selectedAgentID = "helper"
        let draft = HomeTaskDraft()
        draft.text = "  Home task  "
        var opened: String?
        let accepted = await draft.submit(sessions: sessions, connected: true, send: { session, text, uploads, _ in
            #expect(session.agentId == "main")
            #expect(text == "Home task")
            #expect(uploads.isEmpty)
        }, open: { opened = $0 })
        #expect(accepted)
        #expect(opened?.hasPrefix("agent:main:") == true)
        #expect(sessions.selectedAgentID == "helper")
        #expect(fake.receivedRequests.first { $0.method == "sessions.create" }?.params?["agentId"]?.stringValue == "main")
        #expect(!fake.receivedRequests.contains { $0.method == "sessions.patch" })
        #expect(draft.text.isEmpty && !draft.hasFrozenTask)
        await connection.disconnect()
    }

    @Test func explicitNilAgentOmitsWireKeyRatherThanUsingSelectedAgent() async throws {
        let (fake, connection, sessions) = try await setup()
        defer { fake.stop() }
        sessions.selectedAgentID = "helper"
        let key = try #require(await sessions.create(agentID: nil))
        #expect(key.hasPrefix("agent:main:"))
        #expect(fake.receivedRequests.last?.params?["agentId"] == nil)
        #expect(sessions.selectedAgentID == "helper")
        await connection.disconnect()
    }

    @Test func failureAndRetryFreezeSessionAgentModelUploadsAndMessageIdentity() async throws {
        let (fake, connection, sessions) = try await setup()
        defer { fake.stop() }
        let draft = HomeTaskDraft()
        let upload = try await AttachmentPipeline().prepare(data: Data("upload".utf8), fileName: "Notes.txt", limits: nil)
        draft.text = "Original"
        draft.attachments = [upload]
        draft.selectedModelID = "test/fake-model"
        var capturedKey: String?
        var capturedSession: String?
        let firstAccepted = await draft.submit(sessions: sessions, connected: true, send: { session, text, attachments, key in
            capturedKey = key; capturedSession = session.key
            #expect(text == "Original" && attachments == [upload])
            throw Failed()
        }, open: { _ in Issue.record("A rejected task must stay on Home") })
        #expect(!firstAccepted)
        #expect(draft.text == "Original" && draft.attachments == [upload])
        #expect(draft.hasFrozenTask && draft.errorMessage == "Task rejected")
        sessions.selectedAgentID = "helper"
        let retryAccepted = await draft.submit(sessions: sessions, connected: true, send: { session, text, attachments, key in
            #expect(session.key == capturedSession && key == capturedKey)
            #expect(session.agentId == "main" && text == "Original" && attachments == [upload])
        }, open: { #expect($0 == capturedSession) })
        #expect(retryAccepted)
        #expect(fake.receivedRequests.filter { $0.method == "sessions.create" }.count == 1)
        #expect(fake.receivedRequests.filter { $0.method == "sessions.patch" }.count == 1)
        #expect(draft.attachments.isEmpty && draft.text.isEmpty)
        await connection.disconnect()
    }

    @Test func modelPatchFailureKeepsDraftAndDoesNotSendOrOpen() async throws {
        let (fake, connection, sessions) = try await setup()
        defer { fake.stop() }
        fake.fail("sessions.patch", with: .init(code: .forbidden, message: "Model denied"))
        let draft = HomeTaskDraft()
        draft.text = "Model task"
        draft.selectedModelID = "test/fake-model"
        let firstAccepted = await draft.submit(sessions: sessions, connected: true, send: { _, _, _, _ in Issue.record("Patch failure sent a message") },
                                               open: { _ in Issue.record("Patch failure opened a chat") })
        #expect(!firstAccepted)
        #expect(draft.text == "Model task")
        #expect(draft.errorMessage != nil)
        let key = draft.pendingSessionKey
        fake.clearFailure(for: "sessions.patch")
        let retryAccepted = await draft.submit(sessions: sessions, connected: true, send: { session, _, _, _ in #expect(session.key == key) }, open: { _ in })
        #expect(retryAccepted)
        #expect(fake.receivedRequests.filter { $0.method == "sessions.create" }.count == 1)
        #expect(fake.receivedRequests.filter { $0.method == "sessions.patch" }.count == 2)
        await connection.disconnect()
    }

    @Test func resetOrDeletionWithMissingSessionIDRequiresExplicitNewTask() async throws {
        let (fake, connection, sessions) = try await setup()
        defer { fake.stop() }
        fake.reply(to: "sessions.create", withSequence: [.object(["key": .string("agent:main:without-id")])])
        let draft = HomeTaskDraft()
        draft.text = "Keep me"
        let firstAccepted = await draft.submit(sessions: sessions, connected: true, send: { session, _, _, _ in
            #expect(session.sessionId == nil); throw Failed()
        }, open: { _ in })
        #expect(!firstAccepted)
        draft.invalidateSession("agent:main:without-id")
        let retryAccepted = await draft.submit(sessions: sessions, connected: true, send: { _, _, _, _ in Issue.record("Invalidated retry was sent") }, open: { _ in })
        #expect(!retryAccepted)
        #expect(draft.text == "Keep me")
        #expect(draft.errorMessage?.contains("reset or deleted") == true)
        draft.editAsNewTask()
        #expect(!draft.hasFrozenTask && draft.errorMessage == nil && draft.text == "Keep me")
        await connection.disconnect()
    }

    @Test func offlineAndEmptyDraftMakeNoRequests() async throws {
        let (fake, connection, sessions) = try await setup()
        defer { fake.stop() }
        let draft = HomeTaskDraft()
        let initial = fake.receivedRequests.count
        let emptyAccepted = await draft.submit(sessions: sessions, connected: true, send: { _, _, _, _ in }, open: { _ in })
        #expect(!emptyAccepted)
        draft.text = "Offline draft"
        let offlineAccepted = await draft.submit(sessions: sessions, connected: false, send: { _, _, _, _ in }, open: { _ in })
        #expect(!offlineAccepted)
        #expect(fake.receivedRequests.count == initial && draft.text == "Offline draft")
        await connection.disconnect()
    }

    @Test func createFailureKeepsOriginalCreationIdentityOnRetry() async throws {
        let (fake, connection, sessions) = try await setup()
        defer { fake.stop() }
        fake.fail("sessions.create", with: .init(code: .unavailable, message: "Creation interrupted"))
        let draft = HomeTaskDraft()
        draft.text = "Creation retry"
        let firstAccepted = await draft.submit(sessions: sessions, connected: true, send: { _, _, _, _ in Issue.record("Failed creation sent") }, open: { _ in })
        #expect(!firstAccepted)
        #expect(draft.text == "Creation retry" && draft.hasFrozenTask)
        let originalParams = fake.receivedRequests.last?.params
        sessions.selectedAgentID = "helper"
        fake.clearFailure(for: "sessions.create")
        let retryAccepted = await draft.submit(sessions: sessions, connected: true, send: { session, _, _, _ in #expect(session.agentId == "main") }, open: { _ in })
        #expect(retryAccepted)
        let creationRequests = fake.receivedRequests.filter { $0.method == "sessions.create" }
        #expect(creationRequests.count == 2 && creationRequests.last?.params == originalParams)
        await connection.disconnect()
    }

    @Test func lostCreationResponseRetriesToTheAlreadyCreatedSession() async throws {
        let (fake, connection, sessions) = try await setup()
        defer { fake.stop() }
        fake.pauseResponses(to: "sessions.create")
        let draft = HomeTaskDraft()
        draft.text = "Lost creation acknowledgment"
        let first = Task { await draft.submit(sessions: sessions, connected: true,
            send: { _, _, _, _ in Issue.record("Unacknowledged creation sent a message") }, open: { _ in }) }
        let deadline = ContinuousClock.now + .seconds(5)
        while !fake.receivedRequests.contains(where: { $0.method == "sessions.create" }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(fake.receivedRequests.contains { $0.method == "sessions.create" })
        await sessions.loadList()
        let created = try #require(sessions.sessions.first { $0.key != SessionKey.main.rawValue })
        first.cancel()
        #expect(!(await first.value))
        fake.resumeResponses(to: "sessions.create")
        let retryAccepted = await draft.submit(sessions: sessions, connected: true, send: { session, _, _, _ in
            #expect(session.key == created.key && session.sessionId == created.sessionId)
        }, open: { #expect($0 == created.key) })
        #expect(retryAccepted)
        await sessions.loadList()
        #expect(sessions.sessions.filter { $0.key != SessionKey.main.rawValue }.count == 1)
        let creations = fake.receivedRequests.filter { $0.method == "sessions.create" }
        #expect(creations.count == 2 && creations[0].params == creations[1].params)
        await connection.disconnect()
    }
}
