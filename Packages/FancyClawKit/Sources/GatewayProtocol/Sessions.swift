import Foundation

/// Parameters of `sessions.list` (and the snapshot half of `sessions.subscribe`).
public struct SessionsListParams: Codable, Hashable, Sendable {
    public var limit: Int?
    public var offset: Int?
    public var search: String?
    public var includeDerivedTitles: Bool?
    public var includeLastMessage: Bool?
    public var excludeSubagents: Bool?
    public var excludeCron: Bool?
    public var excludeSystem: Bool?

    public init(
        limit: Int? = nil, offset: Int? = nil, search: String? = nil, includeDerivedTitles: Bool? = nil,
        includeLastMessage: Bool? = nil, excludeSubagents: Bool? = nil, excludeCron: Bool? = nil,
        excludeSystem: Bool? = nil
    ) {
        self.limit = limit
        self.offset = offset
        self.search = search
        self.includeDerivedTitles = includeDerivedTitles
        self.includeLastMessage = includeLastMessage
        self.excludeSubagents = excludeSubagents
        self.excludeCron = excludeCron
        self.excludeSystem = excludeSystem
    }

    /// The roster query the session drawer uses: titled, previewed, user-facing chats only.
    public static func drawer(limit: Int = 60, offset: Int = 0, search: String? = nil) -> SessionsListParams {
        SessionsListParams(
            limit: limit, offset: offset, search: search, includeDerivedTitles: true, includeLastMessage: true,
            excludeSubagents: true, excludeCron: true, excludeSystem: true)
    }
}

/// The result of `sessions.list`.
public struct SessionsListResult: Codable, Hashable, Sendable {
    public var sessions: [SessionSummary]
    public var hasMore: Bool?
    public var nextOffset: Int?
    public var totalCount: Int?

    public init(sessions: [SessionSummary], hasMore: Bool? = nil, nextOffset: Int? = nil, totalCount: Int? = nil) {
        self.sessions = sessions
        self.hasMore = hasMore
        self.nextOffset = nextOffset
        self.totalCount = totalCount
    }
}

/// The parts of a Gateway `SessionRow` FancyClaw shows. The row is an open object with ~90 fields; the
/// rest are ignored.
public struct SessionSummary: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var kind: SessionKind?
    public var sessionId: String?
    public var agentId: String?
    public var label: String?
    public var displayName: String?
    public var derivedTitle: String?
    public var lastMessagePreview: String?
    /// Milliseconds since 1970.
    public var updatedAt: Double?
    /// Milliseconds since 1970.
    public var lastActivityAt: Double?
    public var status: SessionRunStatus?
    public var model: String?
    public var pinned: Bool?
    public var unread: Bool?
    public var archived: Bool?
    public var hasActiveRun: Bool?
    public var activeRunIds: [String]?

    public init(
        key: String, kind: SessionKind? = nil, sessionId: String? = nil, agentId: String? = nil,
        label: String? = nil, displayName: String? = nil, derivedTitle: String? = nil,
        lastMessagePreview: String? = nil, updatedAt: Double? = nil, lastActivityAt: Double? = nil,
        status: SessionRunStatus? = nil, model: String? = nil, pinned: Bool? = nil, unread: Bool? = nil,
        archived: Bool? = nil, hasActiveRun: Bool? = nil, activeRunIds: [String]? = nil
    ) {
        self.key = key
        self.kind = kind
        self.sessionId = sessionId
        self.agentId = agentId
        self.label = label
        self.displayName = displayName
        self.derivedTitle = derivedTitle
        self.lastMessagePreview = lastMessagePreview
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
        self.status = status
        self.model = model
        self.pinned = pinned
        self.unread = unread
        self.archived = archived
        self.hasActiveRun = hasActiveRun
        self.activeRunIds = activeRunIds
    }

    public var id: String { key }

    /// The name to show: `label`, then `displayName`, then `derivedTitle`, else `nil` for "New chat".
    public var title: String? {
        [label, displayName, derivedTitle]
            .lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    public var updatedDate: Date? { updatedAt.map(Date.init(gatewayMilliseconds:)) }
}

public enum SessionKind: OpenEnum {
    case direct
    case group
    case global
    /// The Gateway couldn't classify the session (`"unknown"` on the wire).
    case unclassified
    case unknown(String)

    public static let knownCases: [SessionKind] = [.direct, .group, .global, .unclassified]

    public var rawValue: String {
        switch self {
        case .direct: "direct"
        case .group: "group"
        case .global: "global"
        case .unclassified: "unknown"
        case .unknown(let value): value
        }
    }
}

/// The state of a session's most recent run.
public enum SessionRunStatus: OpenEnum {
    case queued
    case running
    case done
    case failed
    case killed
    case timeout
    case unknown(String)

    public static let knownCases: [SessionRunStatus] = [.queued, .running, .done, .failed, .killed, .timeout]

    public var rawValue: String {
        switch self {
        case .queued: "queued"
        case .running: "running"
        case .done: "done"
        case .failed: "failed"
        case .killed: "killed"
        case .timeout: "timeout"
        case .unknown(let value): value
        }
    }
}
