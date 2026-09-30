import Foundation
import SwiftData

@Model public final class CachedSession {
    @Attribute(.unique) public var id: String
    public var gateway: String
    public var key: String
    public var payload: Data
    public init(gateway: String, key: String, payload: Data) {
        id = gateway + "|" + key
        self.gateway = gateway; self.key = key; self.payload = payload
    }
}
