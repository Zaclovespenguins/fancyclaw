import Foundation
import SwiftData

@Model public final class CachedHistory {
    @Attribute(.unique) public var id: String
    public var gateway: String
    public var sessionKey: String
    public var payload: Data
    public init(gateway: String, sessionKey: String, payload: Data) {
        id = gateway + "|" + sessionKey
        self.gateway = gateway; self.sessionKey = sessionKey; self.payload = payload
    }
}
