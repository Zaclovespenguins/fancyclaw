/// A user or assistant text row in the visible conversation.
public struct ConversationMessage: Identifiable, Sendable, Hashable {
    public var id: String
    public let role: MessageRole
    public var text: String
    public var isStreaming: Bool

    public init(id: String, role: MessageRole, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}
