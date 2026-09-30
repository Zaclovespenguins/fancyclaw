import AppIntents

/// OpenIntent guarantees a Control Center action runs in the containing app.
public struct NewChatIntent: OpenIntent {
    public static let title: LocalizedStringResource = "New FancyClaw Chat"
    public static let description = IntentDescription("Open FancyClaw and create a new chat.")
    public static var supportedModes: IntentModes { .foreground(.immediate) }
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title: "Destination", default: .newChat)
    public var target: NewChatDestination
    @Dependency private var service: NewChatAction

    public init() {}
    public init(service: NewChatAction) { self.service = service }

    @MainActor public func perform() async throws -> some IntentResult {
        try await service.create()
        return .result()
    }
}
