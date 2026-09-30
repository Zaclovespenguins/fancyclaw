import Foundation

/// Parameters of `chat.send`.
public struct ChatSendParams: Codable, Hashable, Sendable {
    public var sessionKey: String
    public var message: String
    /// Reuse the same key when retrying so the Gateway deduplicates the turn.
    public var idempotencyKey: String
    public var attachments: [ChatAttachment]?
    public var thinking: String?
    public var queueMode: QueueMode?

    public init(
        sessionKey: String, message: String, idempotencyKey: String = UUID().uuidString,
        attachments: [ChatAttachment]? = nil, thinking: String? = nil, queueMode: QueueMode? = nil
    ) {
        self.sessionKey = sessionKey
        self.message = message
        self.idempotencyKey = idempotencyKey
        self.attachments = attachments
        self.thinking = thinking
        self.queueMode = queueMode
    }
}

/// How a message sent during an active run is handled.
public enum QueueMode: String, Codable, Hashable, Sendable, CaseIterable {
    case steer, followup, collect, interrupt
}

/// An inline attachment on `chat.send`. Keep each within `policy.attachments` and the frame within
/// `policy.maxPayload`.
public struct ChatAttachment: Codable, Hashable, Sendable {
    public var type: String?
    public var mimeType: String?
    public var fileName: String?
    public var origin: Origin?
    /// Base64-encoded bytes.
    public var content: String?
    public var sizeBytes: Int?
    public var width: Int?
    public var height: Int?
    public var durationMs: Int?

    public init(
        type: String? = nil, mimeType: String? = nil, fileName: String? = nil, origin: Origin? = nil,
        content: String? = nil, sizeBytes: Int? = nil, width: Int? = nil, height: Int? = nil,
        durationMs: Int? = nil
    ) {
        self.type = type
        self.mimeType = mimeType
        self.fileName = fileName
        self.origin = origin
        self.content = content
        self.sizeBytes = sizeBytes
        self.width = width
        self.height = height
        self.durationMs = durationMs
    }

    public enum Origin: String, Codable, Hashable, Sendable {
        case paste, file
    }
}

/// The acknowledgment of `chat.send`.
public struct ChatSendResponse: Codable, Hashable, Sendable {
    /// Adopt this id if it differs from the idempotency key that was sent.
    public var runId: String
    public var status: ChatSendStatus

    public init(runId: String, status: ChatSendStatus) {
        self.runId = runId
        self.status = status
    }
}

public enum ChatSendStatus: OpenEnum {
    /// A new run started.
    case started
    /// The turn was queued behind an active run.
    case accepted
    /// A retry of a turn that is still running.
    case inFlight
    /// A retry of a turn that already finished.
    case ok
    case unknown(String)

    public static let knownCases: [ChatSendStatus] = [.started, .accepted, .inFlight, .ok]

    public var rawValue: String {
        switch self {
        case .started: "started"
        case .accepted: "accepted"
        case .inFlight: "in_flight"
        case .ok: "ok"
        case .unknown(let value): value
        }
    }
}

/// Parameters of `chat.abort`.
public struct ChatAbortParams: Codable, Hashable, Sendable {
    public var sessionKey: String
    public var runId: String?

    public init(sessionKey: String, runId: String? = nil) {
        self.sessionKey = sessionKey
        self.runId = runId
    }
}

/// Parameters of `chat.history`.
///
/// Pass `offset` to page older messages, or `cursor` (a previous `deltaCursor`) to catch up.
public struct ChatHistoryParams: Codable, Hashable, Sendable {
    public var sessionKey: String
    public var cursor: String?
    public var limit: Int?
    public var offset: Int?

    public init(sessionKey: String, cursor: String? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.sessionKey = sessionKey
        self.cursor = cursor
        self.limit = limit
        self.offset = offset
    }
}

/// A page of `chat.history`, returned when no `cursor` is passed.
public struct ChatHistoryPage: Codable, Hashable, Sendable {
    public var sessionKey: String
    public var sessionId: String?
    public var messages: [ChatMessage]
    public var sessionInfo: ChatSessionInfo?
    public var inFlightRun: JSONValue?
    public var hasMore: Bool?
    public var nextOffset: Int?
    /// Pass back as `cursor` to fetch only what changed.
    public var deltaCursor: String?

    public init(
        sessionKey: String, sessionId: String? = nil, messages: [ChatMessage], sessionInfo: ChatSessionInfo? = nil,
        inFlightRun: JSONValue? = nil, hasMore: Bool? = nil, nextOffset: Int? = nil, deltaCursor: String? = nil
    ) {
        self.sessionKey = sessionKey
        self.sessionId = sessionId
        self.messages = messages
        self.sessionInfo = sessionInfo
        self.inFlightRun = inFlightRun
        self.hasMore = hasMore
        self.nextOffset = nextOffset
        self.deltaCursor = deltaCursor
    }
}

public struct ChatSessionInfo: Codable, Hashable, Sendable {
    public var key: String
    public var agentId: String?
    public var hasActiveRun: Bool?
    public var activeRunIds: [String]?

    public init(key: String, agentId: String? = nil, hasActiveRun: Bool? = nil, activeRunIds: [String]? = nil) {
        self.key = key
        self.agentId = agentId
        self.hasActiveRun = hasActiveRun
        self.activeRunIds = activeRunIds
    }
}

/// The `chat.history` result when a `cursor` is passed.
public enum ChatHistoryCatchUp: Hashable, Sendable {
    /// Messages added or changed since the cursor.
    case delta(Delta)
    /// The cursor is too old; refetch the tail.
    case reset
    case unknown(String)

    public struct Delta: Codable, Hashable, Sendable {
        public var messages: [ChatMessage]
        public var deltaCursor: String
        public var sessionInfo: ChatSessionInfo?
        public var inFlightRun: JSONValue?

        public init(messages: [ChatMessage], deltaCursor: String, sessionInfo: ChatSessionInfo? = nil, inFlightRun: JSONValue? = nil) {
            self.messages = messages
            self.deltaCursor = deltaCursor
            self.sessionInfo = sessionInfo
            self.inFlightRun = inFlightRun
        }
    }
}

extension ChatHistoryCatchUp: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: any Decoder) throws {
        let kind = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .kind)
        switch kind {
        case "delta": self = .delta(try Delta(from: decoder))
        case "reset": self = .reset
        default: self = .unknown(kind)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .delta(let delta):
            try container.encode("delta", forKey: .kind)
            try delta.encode(to: encoder)
        case .reset:
            try container.encode("reset", forKey: .kind)
        case .unknown(let kind):
            try container.encode(kind, forKey: .kind)
        }
    }
}
