import AppIntents

public struct OpenSessionIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open FancyClaw Chat"
    public static let description = IntentDescription("Open a cached FancyClaw conversation.")
    public static var supportedModes: IntentModes { .foreground(.immediate) }
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    public static var parameterSummary: some ParameterSummary { Summary("Open \(\.$target)") }

    @Parameter(title: "Chat") public var target: SessionEntity
    @Dependency private var service: IntentService

    public init() {}
    public init(target: SessionEntity, service: IntentService) {
        self.target = target
        self.service = service
    }

    @MainActor public func perform() async throws -> some IntentResult {
        try await service.openSession(target)
        return .result()
    }
}
