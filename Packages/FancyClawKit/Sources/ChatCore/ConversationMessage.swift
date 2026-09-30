import GatewayProtocol

/// A user or assistant rich output row in the visible conversation.
public struct ConversationMessage: Identifiable, Sendable, Hashable {
    public var id: String
    public let role: MessageRole
    public var text: String
    public var isStreaming: Bool
    public var images: [ContentBlock.Media]
    public var files: [ContentBlock.Media]
    public var attachments: [PreparedAttachment]
    public var tools: [ConversationTool]

    public init(id: String, role: MessageRole, text: String, isStreaming: Bool = false,
                images: [ContentBlock.Media] = [], attachments: [PreparedAttachment] = [], files: [ContentBlock.Media] = [], tools: [ConversationTool] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.files = files
        self.images = images
        self.attachments = attachments
        self.tools = tools
    }
}

public extension ConversationMessage {
    /// Textual owns Markdown parsing. Thinking and non-text blocks never enter the string.
    static func markdown(from message: ChatMessage) -> String {
        message.content.compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.joined(separator: "\n\n")
    }

    static func files(from message: ChatMessage) -> [ContentBlock.Media] {
        message.content.compactMap { block in
            if case .media(let media) = block, media.kind != .image { return media }
            return nil
        }
    }

    static func images(from message: ChatMessage) -> [ContentBlock.Media] {
        message.content.compactMap { block in
            if case .media(let media) = block, media.kind == .image { return media }
            return nil
        }
    }
}
