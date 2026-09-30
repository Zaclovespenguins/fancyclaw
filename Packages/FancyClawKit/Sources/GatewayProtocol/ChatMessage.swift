/// A transcript entry, as returned by `chat.history` and carried by `chat` events.
///
/// Messages are open objects on the wire; unmodeled fields are ignored.
public struct ChatMessage: Codable, Hashable, Sendable {
    public var role: ChatRole
    public var content: [ContentBlock]
    /// Milliseconds since 1970.
    public var timestamp: Double?
    public var model: String?
    public var toolCallId: String?
    public var toolName: String?
    public var usage: JSONValue?
    public var stopReason: String?
    public var errorMessage: String?
    public var isError: Bool?
    public var idempotencyKey: String?
    /// Gateway bookkeeping (`__openclaw`), including the stable entry id.
    public var metadata: Metadata?

    public init(
        role: ChatRole, content: [ContentBlock], timestamp: Double? = nil, model: String? = nil,
        toolCallId: String? = nil, toolName: String? = nil, usage: JSONValue? = nil, stopReason: String? = nil,
        errorMessage: String? = nil, isError: Bool? = nil, idempotencyKey: String? = nil, metadata: Metadata? = nil
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.model = model
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.usage = usage
        self.stopReason = stopReason
        self.errorMessage = errorMessage
        self.isError = isError
        self.idempotencyKey = idempotencyKey
        self.metadata = metadata
    }

    /// The stable transcript entry id, used for identity and cache keys.
    public var entryId: String? { metadata?.id }

    private enum CodingKeys: String, CodingKey {
        case role, content, timestamp, model, toolCallId, toolName, usage, stopReason, errorMessage, isError
        case idempotencyKey
        case metadata = "__openclaw"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(ChatRole.self, forKey: .role)
        // Some producers store plain-text content as a bare string.
        if let text = try? container.decode(String.self, forKey: .content) {
            content = [.text(text)]
        } else {
            content = try container.decodeIfPresent([ContentBlock].self, forKey: .content) ?? []
        }
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        usage = try container.decodeIfPresent(JSONValue.self, forKey: .usage)
        stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)
        metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
    }

    public struct Metadata: Codable, Hashable, Sendable {
        public var id: String?
        public var runId: String?
        public var kind: String?

        public init(id: String? = nil, runId: String? = nil, kind: String? = nil) {
            self.id = id
            self.runId = runId
            self.kind = kind
        }
    }
}

public enum ChatRole: OpenEnum {
    case user
    case assistant
    case toolResult
    case system
    case unknown(String)

    public static let knownCases: [ChatRole] = [.user, .assistant, .toolResult, .system]

    public var rawValue: String {
        switch self {
        case .user: "user"
        case .assistant: "assistant"
        case .toolResult: "toolResult"
        case .system: "system"
        case .unknown(let value): value
        }
    }
}

/// One block of a message's `content` array, discriminated on `type`.
public enum ContentBlock: Hashable, Sendable {
    case text(String)
    case thinking(String)
    case toolCall(ToolCall)
    case media(Media)
    /// A block type FancyClaw doesn't model, kept verbatim so it round-trips.
    case unknown(type: String, JSONValue)

    public struct ToolCall: Codable, Hashable, Sendable {
        public var id: String?
        public var name: String?
        public var arguments: JSONValue?

        public init(id: String? = nil, name: String? = nil, arguments: JSONValue? = nil) {
            self.id = id
            self.name = name
            self.arguments = arguments
        }
    }

    /// An image, audio, video or file block. History returns URLs or artifact ids, not inline bytes.
    public struct Media: Codable, Hashable, Sendable {
        public var kind: MediaKind
        public var mimeType: String?
        public var fileName: String?
        public var artifactId: String?
        /// Often relative to the Gateway and short-lived, for example `/api/chat/media/outgoing/…/full`.
        public var url: String?
        public var alt: String?
        public var width: Int?
        public var height: Int?
        public var sizeBytes: Int?

        public init(
            kind: MediaKind, mimeType: String? = nil, fileName: String? = nil, artifactId: String? = nil,
            url: String? = nil, alt: String? = nil, width: Int? = nil, height: Int? = nil, sizeBytes: Int? = nil
        ) {
            self.kind = kind
            self.mimeType = mimeType
            self.fileName = fileName
            self.artifactId = artifactId
            self.url = url
            self.alt = alt
            self.width = width
            self.height = height
            self.sizeBytes = sizeBytes
        }

        private enum CodingKeys: String, CodingKey {
            case kind = "type"
            case mimeType, fileName, artifactId, url, alt, width, height, sizeBytes
        }
    }

    public enum MediaKind: String, Codable, Hashable, Sendable, CaseIterable {
        case image, audio, video, file
    }
}

extension ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, thinking, id, name, arguments
    }

    /// Spellings of the tool-call block type seen across providers.
    private static let toolCallTypes: Set<String> = ["toolCall", "tool_use", "tooluse", "tool_call"]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "thinking":
            self = .thinking(try container.decodeIfPresent(String.self, forKey: .thinking) ?? "")
        case _ where Self.toolCallTypes.contains(type):
            self = .toolCall(ToolCall(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                name: try container.decodeIfPresent(String.self, forKey: .name),
                arguments: try container.decodeIfPresent(JSONValue.self, forKey: .arguments)))
        case _ where MediaKind(rawValue: type) != nil:
            self = .media(try Media(from: decoder))
        default:
            self = .unknown(type: type, try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .thinking(let thinking):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("thinking", forKey: .type)
            try container.encode(thinking, forKey: .thinking)
        case .toolCall(let call):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("toolCall", forKey: .type)
            try container.encodeIfPresent(call.id, forKey: .id)
            try container.encodeIfPresent(call.name, forKey: .name)
            try container.encodeIfPresent(call.arguments, forKey: .arguments)
        case .media(let media):
            try media.encode(to: encoder)
        case .unknown(_, let raw):
            try raw.encode(to: encoder)
        }
    }
}
