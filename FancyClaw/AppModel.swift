import ChatCore
import Foundation
import GatewayClient
import GatewayProtocol
import Observation
#if DEBUG
import TestSupport
#endif

@Observable
final class AppModel {
    private(set) var conversation: ConversationStore?
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
                fake.reply(to: "chat.history", with: .object([
                    "sessionKey": .string(SessionKey.main.rawValue), "messages": .array([])
                ]))
                self.fake = fake
                initialProfile = GatewayProfile(url: try await fake.start(), token: "test-token")
                if ProcessInfo.processInfo.arguments.contains("-DemoConversation"), let initialProfile {
                    let connection = GatewayConnection(identity: .generate())
                    let hello = try await connection.connect(to: initialProfile.url, token: initialProfile.token)
                    await activate(profile: initialProfile, connection: connection, hello: hello)
                    await conversation?.send("Hello, FancyClaw")
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
            let hello = try await connection.connect(to: profile.url, token: profile.token,
                bootstrapToken: profile.bootstrapToken, password: profile.password)
            await activate(profile: profile, connection: connection, hello: hello)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activate(profile: GatewayProfile, connection: GatewayConnection, hello: HelloOK) async {
        self.connection = connection
        let conversation = ConversationStore(connection: connection)
        await conversation.start()
        self.conversation = conversation
        let lifecycle = ConnectionLifecycle(connection: connection, resync: { [weak conversation] in
            do {
                let page: ChatHistoryPage = try await connection.request("chat.history",
                    params: ChatHistoryParams(sessionKey: SessionKey.main.rawValue, limit: 100), returning: ChatHistoryPage.self)
                await conversation?.reconcileHistory(page.messages)
            } catch {
                await MainActor.run { conversation?.errorMessage = "Couldn’t refresh the conversation. \(error.localizedDescription)" }
            }
        })
        self.lifecycle = lifecycle
        await lifecycle.start(profile: profile, hello: hello)
        await lifecycle.setForeground(isForeground)
        let statuses = await lifecycle.statuses()
        statusTask = Task { [weak self] in
            for await status in statuses {
                guard !Task.isCancelled else { return }
                self?.status = status
                if status != .connected { self?.conversation?.connectionDidDisconnect() }
            }
        }
        pathTask = Task {
            for await reachable in NetworkAvailability().updates() {
                guard !Task.isCancelled else { return }
                await lifecycle.setReachable(reachable)
            }
        }
    }

    func setForeground(_ value: Bool) async {
        isForeground = value
        await lifecycle?.setForeground(value)
    }

    func disconnect() async {
        statusTask?.cancel()
        pathTask?.cancel()
        await lifecycle?.stop()
        await connection?.disconnect()
        conversation?.stopListening()
        conversation = nil
        lifecycle = nil
        connection = nil
        status = .offline
        if !isTestMode {
            do { try GatewayProfileStore().delete() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
