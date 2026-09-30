/// Injected only in the main app. The control extension contains no cache queries or Gateway code.
@MainActor public final class NewChatAction {
    public let create: () async throws -> Void
    public init(create: @escaping () async throws -> Void) { self.create = create }
}
