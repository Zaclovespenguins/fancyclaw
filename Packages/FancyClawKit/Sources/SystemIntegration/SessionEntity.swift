import AppIntents
import Foundation
import GatewayProtocol
import Persistence

public struct SessionEntity: AppEntity, Hashable, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Chat"
    public static var defaultQuery: SessionEntityQuery { SessionEntityQuery() }
    public let id: String
    public let gateway: String
    public let sessionKey: String
    public let title: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(sessionKey)")
    }

    public init(gateway: String, sessionKey: String, title: String) {
        self.gateway = gateway
        self.sessionKey = sessionKey
        self.title = title
        // Gateway namespacing prevents a saved shortcut from opening the same key on a different server.
        id = gateway + "\n" + sessionKey
    }

    @MainActor public static func cached(in cache: TranscriptCache) throws -> [Self] {
        try cache.sessions().filter { $0.archived != true }.sorted {
            let left = $0.lastActivityAt ?? $0.updatedAt ?? 0
            let right = $1.lastActivityAt ?? $1.updatedAt ?? 0
            return left == right ? $0.key < $1.key : left > right
        }.map { Self(gateway: cache.gateway, sessionKey: $0.key, title: $0.title ?? "New chat") }
    }
}
