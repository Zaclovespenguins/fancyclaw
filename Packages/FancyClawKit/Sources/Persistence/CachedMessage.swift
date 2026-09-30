import Foundation
import SwiftData

@Model public final class CachedMessage {
    @Attribute(.unique) public var id: String
    public var gateway: String
    public var sessionKey: String
    public var position: Int
    public var payload: Data
    public init(gateway: String, sessionKey: String, entryID: String, position: Int, payload: Data) {
        id = gateway + "|" + sessionKey + "|" + entryID
        self.gateway = gateway; self.sessionKey = sessionKey
        self.position = position; self.payload = payload
    }
}
