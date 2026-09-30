import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import Observation
import Persistence
import SwiftData
#if DEBUG
import TestSupport
#endif

@Observable
final class AppModel {
    private(set) var conversation: ConversationStore?
    private(set) var sessions: SessionStore?
    private var cache: TranscriptCache?
    private var cacheContainer: ModelContainer?
    private var conversations: [String: ConversationStore] = [:]
    private(set) var status: ConnectionStatus = .offline
    private(set) var initialProfile: GatewayProfile?
    private(set) var isPreparing = true
    var errorMessage: String?
    private var connection: GatewayConnection?
    private var lifecycle: ConnectionLifecycle?
    private var statusTask: Task<Void, Never>?
    private var pathTask: Task<Void, Never>?
    private var isForeground = true
    private var prepared = false
    private var isTestMode = false
    private var isConnecting = false
    #if DEBUG
    private var fake: FakeGateway?
    #endif

    func prepare() async {
        guard !prepared else { return }
        prepared = true
        defer { isPreparing = false }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-OnboardingPreview") {
                isTestMode = true
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-FakeGateway") || ProcessInfo.processInfo.arguments.contains("-DemoConversation") {
                isTestMode = true
                let hello = try Fixtures.decode(ResponseFrame<HelloOK>.self, from: "hello-ok.res").payload
                guard let hello else { throw ConnectionError.missingPayload }
                let fake = FakeGateway(replies: Array(repeating: .hello(hello), count: 30))
                fake.streamChatReply("Hello from FakeGateway.")
                fake.enableSessions()
                self.fake = fake
                initialProfile = GatewayProfile(url: try await fake.start(), token: "test-token")
                if ProcessInfo.processInfo.arguments.contains("-DemoConversation"), let initialProfile {
                    let connection = GatewayConnection(identity: .generate())
                    let hello = try await connection.connect(to: initialProfile.url, token: initialProfile.token)
                    await activate(profile: initialProfile, connection: connection, hello: hello)
                    await seedRichDemo()
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
        if self.connection !== connection { configure(profile: profile, connection: connection) }
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
        let conversation = ConversationStore(connection: connection, cache: cache, gatewayURL: profile.url)
        conversations[conversation.sessionKey] = conversation
        self.conversation = conversation
    }

    private func resync() async {
        await sessions?.refresh()
        for store in conversations.values { await store.refreshHistory() }
    }

    func selectSession(_ key: String) async {
        guard let connection else { return }
        let store = conversations[key] ?? ConversationStore(connection: connection, sessionKey: key, cache: cache, gatewayURL: initialProfile?.url)
        conversations[key] = store
        conversation = store
        await store.start()
        await store.refreshHistory()
    }

    func newChat() async {
        if let key = await sessions?.create() { await selectSession(key) }
    }

    private func invalidateSession(_ key: String) async {
        conversations.removeValue(forKey: key)?.invalidate()
        guard conversation?.sessionKey == key else { return }
        let next = sessions?.sessions.contains(where: { $0.key == key }) == true ? key : SessionKey.main.rawValue
        await selectSession(next)
    }

    func reconnect() async {
        guard !isConnecting else { return }
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
        isForeground = value
        await lifecycle?.setForeground(value)
        if value && lifecycle == nil && conversation != nil { await reconnect() }
    }

    func disconnect() async {
        statusTask?.cancel()
        pathTask?.cancel()
        await lifecycle?.stop()
        await connection?.disconnect()
        for store in conversations.values { store.stopListening() }
        conversations.removeAll()
        sessions?.stop()
        sessions = nil
        conversation = nil
        cache = nil
        lifecycle = nil
        connection = nil
        status = .offline
        if !isTestMode {
            do { try GatewayProfileStore().delete() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
