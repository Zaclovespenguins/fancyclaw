import AppIntents

public struct AskFancyClawIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask FancyClaw"
    public static let description = IntentDescription("Open FancyClaw and send a message to the default chat.")
    public static var supportedModes: IntentModes { .foreground(.immediate) }
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    public static var parameterSummary: some ParameterSummary { Summary("Ask FancyClaw \(\.$message)") }

    @Parameter(title: "Message", requestValueDialog: "What would you like to ask?")
    public var message: String
    @Dependency private var service: IntentService

    public init() {}
    public init(message: String, service: IntentService) {
        self.message = message
        self.service = service
    }

    @MainActor public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IntentError.emptyMessage }
        let reply = try await service.ask(message)
        return .result(value: reply, dialog: "\(reply)")
    }
}
