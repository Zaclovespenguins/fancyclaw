import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import Observation
import Persistence
import SwiftData
import SystemIntegration
import SystemActions
#if DEBUG
import TestSupport
#endif

@Observable
final class AppModel {
    /// The most recently opened conversation. Intents and the demo modes use it; chat screens render the store their route names.
    private(set) var conversation: ConversationStore?
    let router = AppRouter()
    let linkPreviewLoader = LinkPreviewLoader()
    /// `hello.server.version` from the latest handshake, shown in Settings.
    private(set) var gatewayVersion: String?
    private(set) var sessions: SessionStore?
    private(set) var approvals: ApprovalStore?
    private var cache: TranscriptCache?
    private var cacheContainer: ModelContainer?
    private let activityDriver = ActivityKitDriver()
    private var runActivities: RunActivityStore?
    private var preparationTask: Task<Void, Never>?
    private var conversations: [String: ConversationStore] = [:]
    private(set) var status: ConnectionStatus = .offline
    private(set) var initialProfile: GatewayProfile?
    private(set) var isPreparing = true
    var errorMessage: String?
    private var connection: GatewayConnection?
    private var lifecycle: ConnectionLifecycle?
    private var statusTask: Task<Void, Never>?
    private var pathTask: Task<Void, Never>?
    private var isForeground: Bool { foregroundCoordinator.isForeground }
    @ObservationIgnored private var coordinator: ForegroundCoordinator?
    private var foregroundCoordinator: ForegroundCoordinator {
        if let coordinator { return coordinator }
        let made = ForegroundCoordinator(
            lifecycle: { [weak self] value in await self?.lifecycle?.setForeground(value) },
            backgroundActivities: { [weak self] in await self?.runActivities?.connectionDidDisconnect() })
        coordinator = made
        return made
    }
    private var prepared = false
    private var isTestMode = false
    private var isConnecting = false
    #if DEBUG
    private var fake: FakeGateway?
    #endif

    func prepare() async {
        if let preparationTask { await preparationTask.value; return }
        let task = Task { await prepareOnce() }
        preparationTask = task
        await task.value
    }

    private func prepareOnce() async {
        guard !prepared else { return }
        prepared = true
        defer { isPreparing = false }
        await activityDriver.endOrphanedActivities()
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-OnboardingPreview") {
                isTestMode = true
                return
            }
            let arguments = ProcessInfo.processInfo.arguments
            let demoModes = ["-DemoConversation", "-DemoAttachments", "-DemoApprovals", "-DemoSystemIntegration", "-DemoOffline", "-DemoApprovalFocus", "-DemoSessionActionError", "-DemoLinkPreviews"]
            let isDemo = demoModes.contains(where: arguments.contains)
            if arguments.contains("-FakeGateway") || isDemo {
                isTestMode = true
                let hello = try Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload
                guard let hello else { throw ConnectionError.missingPayload }
                let replies = Array(repeating: FakeGateway.Reply.hello(hello), count: 30)
                let fake = FakeGateway(replies: replies)
                fake.streamChatReply("Hello from FakeGateway.")
                fake.enableSessions()
                if arguments.contains("-DemoSessionActionError") {
                    fake.fail("sessions.patch", with: .init(code: .forbidden, message: "The demo Gateway rejected the chat change."))
                }
                self.fake = fake
                initialProfile = GatewayProfile(url: try await fake.start(), token: "test-token")
                if isDemo, let initialProfile {
                    let connection = GatewayConnection(identity: .generate())
                    let hello = try await connection.connect(to: initialProfile.url, token: initialProfile.token)
                    await activate(profile: initialProfile, connection: connection, hello: hello)
                    if arguments.contains("-DemoOffline") {
                        // Every automatic retry is refused until the person explicitly chooses Reconnect.
                        // This remains deterministic even if launch-time availability callbacks arrive late.
                        fake.refuseConnections(.init(code: .forbidden, message: "The demo Gateway refused to reconnect."))
                        fake.dropConnections()
                        return
                    } else if arguments.contains("-DemoSystemIntegration") {
                        await seedSystemDemo()
                    } else if arguments.contains("-DemoApprovalFocus") {
                        // Opens a long, not-yet-loaded chat focused on its approval card (the approval Review path).
                        await openApprovalFocusDemo()
                        return
                    } else if arguments.contains("-DemoLinkPreviews") {
                        await seedLinkPreviewDemo()
                    } else if arguments.contains("-DemoApprovals") {
                        await seedApprovalDemo()
                    } else if arguments.contains("-DemoAttachments") {
                        let pipeline = AttachmentPipeline()
                        let image = try await pipeline.prepare(data: AttachmentDemo.imageData(), fileName: "Coast.heic",
                                                               imageRequired: true, limits: hello.policy.attachments)
                        let file = try await pipeline.prepare(data: Data("Attachment demo".utf8), fileName: "Notes.txt",
                                                              limits: hello.policy.attachments)
                        conversation?.draftAttachments = [image, file]
                    } else { await seedRichDemo() }
                    // Demo modes show the seeded main chat pushed on Home.
                    await open(sessionKey: SessionKey.main.rawValue)
                }
                return
            }
            #endif
            guard let profile = try GatewayProfileStore().load() else { return }
            let identityStore = DeviceIdentityStore()
            let session: URLSession
            if let fingerprint = profile.tlsFingerprint {
                session = URLSession(configuration: .default, delegate: GatewayTLSDelegate(fingerprint: fingerprint), delegateQueue: nil)
            } else {
                session = .shared
            }
            let connection = GatewayConnection(identity: try identityStore.loadOrCreate(), identityStore: identityStore, session: session)
            configure(profile: profile, connection: connection)
            isPreparing = false
            isConnecting = true
            defer { isConnecting = false }
            let hello = try await connection.connect(to: profile.url, token: profile.token,
                bootstrapToken: profile.bootstrapToken, password: profile.password)
            guard self.connection === connection else { return }
            await activate(profile: profile, connection: connection, hello: hello)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    private func seedLinkPreviewDemo() async {
        guard let conversation, let fake else { return }
        fake.seedHistory(LinkPreviewDemo.history, sessionKey: conversation.sessionKey, activeRunID: "demo-link-stream")
        conversation.reconcileHistory(LinkPreviewDemo.history)
        conversation.receive(LinkPreviewDemo.partialStream(sessionKey: conversation.sessionKey))
    }

    private func seedSystemDemo() async {
        guard let fake else { return }
        fake.seedHistory([ChatMessage(role: .user, content: [.text("Show a Live Activity for this reply.")],
            metadata: .init(id: "demo-system-user"))], sessionKey: SessionKey.main.rawValue, activeRunID: "demo-system-run")
        await resync()
        fake.emit(.init(event: .agent(.init(runId: "demo-system-run", seq: 1, stream: "lifecycle",
            sessionKey: SessionKey.main.rawValue, agentId: "main", data: ["phase": "start",
                "startedAt": .integer(Int(Date.now.timeIntervalSince1970 * 1_000))]))))
        fake.emit(.init(event: .chat(.init(runId: "demo-system-run", sessionKey: SessionKey.main.rawValue,
            seq: 1, state: .delta(.init(deltaText: "This demo run keeps a Live Activity visible. Stop the reply to end it."))))))
    }

    private func seedApprovalDemo() async {
        guard let fake, let sessions else { return }
        await sessions.refresh()
        let otherKey = await sessions.create()
        let created = Int(Date.now.timeIntervalSince1970 * 1000)
        fake.requestApproval(.init(id: "demo-approval", createdAtMs: created, expiresAtMs: created + 120_000,
            request: .init(command: "swift --version", cwd: "/tmp/fancyclaw-demo", host: "Gateway",
                warningText: "The assistant wants to run this command on the Gateway.",
                allowedDecisions: [.allowOnce, .deny], sessionKey: SessionKey.main.rawValue)))
        if let otherKey {
            fake.requestApproval(.init(id: "demo-other-approval", createdAtMs: created, expiresAtMs: created + 120_000,
                request: .init(command: "pwd", allowedDecisions: [.allowOnce, .deny], sessionKey: otherKey)))
        }
    }

    private func openApprovalFocusDemo() async {
        guard let fake, let sessions else { return }
        await sessions.refresh()
        guard let key = await sessions.create() else { return }
        fake.seedHistory((0..<30).flatMap { index -> [ChatMessage] in
            [ChatMessage(role: .user, content: [.text("Question \(index + 1)")], metadata: .init(id: "focus-user-\(index)")),
             ChatMessage(role: .assistant, content: [.text("Answer \(index + 1). This reply is long enough to take a few lines of the transcript, so the approval at the end starts far from the top of the chat.")],
                         metadata: .init(id: "focus-assistant-\(index)"))]
        }, sessionKey: key)
        let created = Int(Date.now.timeIntervalSince1970 * 1000)
        fake.requestApproval(.init(id: "demo-focus-approval", createdAtMs: created, expiresAtMs: created + 300_000,
            request: .init(command: "git push origin fix/date-parser", commandPreview: "Push fix to photo-sync",
                host: "Gateway", allowedDecisions: [.allowOnce, .allowAlways, .deny], sessionKey: key)))
        for _ in 0..<60 where approvals?.approvals.contains(where: { $0.id == "demo-focus-approval" }) != true {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await open(sessionKey: key, focusApproval: "demo-focus-approval")
    }

    private func seedRichDemo() async {
        // Seed the fake's canonical history too, so a lifecycle resync retains the showcase.
        guard let conversation, let fake else { return }
        let history = RichConversationDemo.history
        fake.seedHistory(history, sessionKey: conversation.sessionKey, activeRunID: "demo-partial")
        conversation.reconcileHistory(history)
        conversation.receive(RichConversationDemo.partialStream(sessionKey: conversation.sessionKey))
        for event in RichConversationDemo.toolEvents(sessionKey: conversation.sessionKey) { conversation.receive(event) }
    }
    #endif

    func activate(profile: GatewayProfile, connection: GatewayConnection, hello: HelloOK) async {
        if self.connection !== connection {
            await runActivities?.stop()
            configure(profile: profile, connection: connection)
        }
        status = .connected
        gatewayVersion = hello.server.version
        await runActivities?.start()
        approvals?.updateScopes(hello.auth.scopes)
        await approvals?.start()
        await conversation?.start()
        await sessions?.start()
        let lifecycle = ConnectionLifecycle(connection: connection, resync: { [weak self] in
            await self?.resync()
        })
        self.lifecycle = lifecycle
        await lifecycle.start(profile: profile, hello: hello)
        await lifecycle.setForeground(isForeground)
        let statuses = await lifecycle.statuses()
        statusTask = Task { [weak self] in
            for await status in statuses {
                guard !Task.isCancelled else { return }
                self?.status = status
                if status != .connected {
                    for store in self?.conversations.values ?? [:].values { store.connectionDidDisconnect() }
                    await self?.runActivities?.connectionDidDisconnect()
                }
            }
        }
        Task { [weak self] in
            await self?.resync()
            await self?.sessions?.loadCatalogs()
        }
        pathTask = Task {
            for await reachable in NetworkAvailability().updates() {
                guard !Task.isCancelled else { return }
                await lifecycle.setReachable(reachable)
            }
        }
    }

    private func configure(profile: GatewayProfile, connection: GatewayConnection) {
        self.connection = connection
        approvals?.stop()
        approvals = ApprovalStore(connection: connection)
        initialProfile = profile
        do {
            if cacheContainer == nil { cacheContainer = try TranscriptCache.makeContainer(inMemory: isTestMode) }
            if let cacheContainer { cache = TranscriptCache(container: cacheContainer, gateway: profile.url.absoluteString) }
        } catch { errorMessage = "Couldn’t open the chat cache. \(error.localizedDescription)" }
        let sessions = SessionStore(connection: connection, cache: cache)
        sessions.onInvalidatedSession = { [weak self] key in
            await self?.invalidateSession(key)
        }
        self.sessions = sessions
        runActivities = RunActivityStore(connection: connection, driver: activityDriver, agentName: { [weak self] id in
            self?.sessions?.agents.first(where: { $0.id == id })?.name ?? id.capitalized
        })
        let conversation = ConversationStore(connection: connection, cache: cache, gatewayURL: profile.url)
        trackHistoryRuns(in: conversation)
        conversations[conversation.sessionKey] = conversation
        self.conversation = conversation
    }

    private func resync() async {
        if let connection { approvals?.updateScopes(await connection.grantedScopes) }
        approvals?.refreshExpiry()
        await sessions?.refresh()
        let keys = Set(conversations.keys).union(runActivities?.sessionKeys ?? [])
        for key in keys {
            guard let store = conversationStore(for: key) else { continue }
            await store.start()
            await store.refreshHistory()
        }
    }

    func selectSession(_ key: String) async {
        guard let store = conversationStore(for: key) else { return }
        conversation = store
        await store.start()
        await store.refreshHistory()
    }

    /// Selects the session's store and pushes its chat on the destination tab, then loads it.
    func open(sessionKey key: String, focusApproval: String? = nil) async {
        guard let store = conversationStore(for: key) else { return }
        conversation = store
        router.openChat(sessionKey: key, focusApproval: focusApproval)
        await store.start()
        await store.refreshHistory()
    }

    /// Approval Review: opens the approval's chat focused on its card. Returns false when it names no session.
    @discardableResult
    func review(_ approval: ConversationApproval) async -> Bool {
        guard let key = approval.sessionKey, !key.isEmpty else { return false }
        await open(sessionKey: key, focusApproval: approval.id)
        return true
    }

    /// The existing store for a routed chat, without creating one (safe to call from a view body).
    func existingStore(for key: String) -> ConversationStore? { conversations[key] }

    /// Profile host (and port, when explicit) for Settings.
    var gatewayHost: String? {
        guard let url = initialProfile?.url, let host = url.host() else { return nil }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    private func conversationStore(for key: String) -> ConversationStore? {
        guard let connection else { return nil }
        let store = conversations[key] ?? ConversationStore(connection: connection, sessionKey: key, cache: cache, gatewayURL: initialProfile?.url)
        conversations[key] = store
        trackHistoryRuns(in: store)
        return store
    }

    func newChat() async {
        if let key = await sessions?.create() { await open(sessionKey: key) }
    }

    private func trackHistoryRuns(in store: ConversationStore) {
        let key = store.sessionKey
        store.onRunSnapshot = { [weak runActivities] ids in
            runActivities?.applySnapshot(sessionKey: key, activeRunIDs: ids)
        }
    }

    func cachedIntentSessions() throws -> [SessionEntity] {
        let profile = isTestMode ? initialProfile : try GatewayProfileStore().load()
        guard let profile else { return [] }
        if cacheContainer == nil { cacheContainer = try TranscriptCache.makeContainer(inMemory: isTestMode) }
        guard let cacheContainer else { return [] }
        return try SessionEntity.cached(in: TranscriptCache(container: cacheContainer, gateway: profile.url.absoluteString))
    }

    private func requireIntentConnection() async throws {
        await prepare()
        // Warm launches arrive while the socket is still recovering from backgrounding; wait for it, bounded.
        if isForeground == false { await setForeground(true) }
        try await ConnectionWaiter(timing: .continuous).waitUntilConnected(
            status: { [weak self] in self?.status ?? .offline }, hasConnection: { [weak self] in self?.connection != nil })
    }

    func askFromIntent(_ text: String) async throws -> String {
        try await requireIntentConnection()
        await open(sessionKey: SessionKey.main.rawValue)
        guard let conversation = existingStore(for: SessionKey.main.rawValue) else { throw IntentError.notConnected }
        return try await conversation.ask(text)
    }

    func newChatFromIntent() async throws {
        try await requireIntentConnection()
        guard let sessions, let key = await sessions.create() else {
            throw IntentError.failed(sessions?.errorMessage ?? "Couldn’t create a chat.")
        }
        await open(sessionKey: key)
    }

    func openSessionFromIntent(_ entity: SessionEntity) async throws {
        await prepare()
        guard connection != nil else { throw IntentError.notConnected }
        guard try cachedIntentSessions().contains(where: { $0.id == entity.id }) else { throw IntentError.sessionUnavailable }
        await open(sessionKey: entity.sessionKey)
    }

    func openActivityURL(_ url: URL) async {
        guard let key = RunActivityAttributes.sessionKey(from: url) else { return }
        await prepare()
        do {
            guard let entity = try cachedIntentSessions().first(where: { $0.sessionKey == key }) else {
                throw IntentError.sessionUnavailable
            }
            try await openSessionFromIntent(entity)
        } catch { errorMessage = error.localizedDescription }
    }

    private func invalidateSession(_ key: String) async {
        await runActivities?.reconcile(sessionKey: key, activeRunIDs: [])
        conversations.removeValue(forKey: key)?.invalidate()
        let stillExists = sessions?.sessions.contains(where: { $0.key == key }) == true
        let isRouted = router.openSessionKeys.contains(key)
        // A deleted chat leaves every stack; a reset one stays pushed and gets a fresh store.
        if !stillExists { router.closeChats(for: key) }
        if conversation?.sessionKey == key {
            await selectSession(stillExists ? key : SessionKey.main.rawValue)
        } else if stillExists && isRouted, let store = conversationStore(for: key) {
            await store.start()
            await store.refreshHistory()
        }
    }

    func reconnect() async {
        guard !isConnecting else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoOffline") { fake?.refuseConnections(nil) }
        #endif
        if let lifecycle {
            await lifecycle.setForeground(false)
            await lifecycle.setForeground(isForeground)
            return
        }
        guard let connection, let profile = initialProfile else { return }
        isConnecting = true
        status = .reconnecting
        defer { isConnecting = false }
        do {
            let hello = try await connection.connect(to: profile.url, token: profile.token,
                bootstrapToken: profile.bootstrapToken, password: profile.password)
            guard self.connection === connection else { return }
            errorMessage = nil
            await activate(profile: profile, connection: connection, hello: hello)
        } catch {
            guard self.connection === connection else { return }
            status = .offline
            errorMessage = error.localizedDescription
        }
    }

    func setForeground(_ value: Bool) async {
        await foregroundCoordinator.set(value)
        if value && isForeground && lifecycle == nil && conversation != nil { await reconnect() }
    }

    func disconnect() async {
        statusTask?.cancel()
        pathTask?.cancel()
        await runActivities?.stop()
        runActivities = nil
        await lifecycle?.stop()
        await connection?.disconnect()
        for store in conversations.values { store.stopListening() }
        conversations.removeAll()
        sessions?.stop()
        approvals?.stop()
        approvals = nil
        sessions = nil
        conversation = nil
        gatewayVersion = nil
        router.reset()
        cache = nil
        lifecycle = nil
        connection = nil
        status = .offline
        if !isTestMode {
            initialProfile = nil
            do { try GatewayProfileStore().delete() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
