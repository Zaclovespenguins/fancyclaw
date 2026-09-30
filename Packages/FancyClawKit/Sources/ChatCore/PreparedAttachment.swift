import Foundation
import GatewayProtocol

/// Prepared upload bytes live only in the draft, optimistic echo, and retry outbox.
public struct PreparedAttachment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let data: Data
    public let thumbnail: Data?
    public let fileName: String
    public let mimeType: String
    public let width: Int?
    public let height: Int?
    public let payload: ChatAttachment

    init(data: Data, thumbnail: Data? = nil, fileName: String, mimeType: String,
         width: Int? = nil, height: Int? = nil) {
        id = UUID()
        self.data = data
        self.thumbnail = thumbnail
        self.fileName = fileName
        self.mimeType = mimeType
        self.width = width
        self.height = height
        payload = ChatAttachment(type: mimeType.hasPrefix("image/") ? "image" : "file", mimeType: mimeType,
                       fileName: fileName, origin: .file, content: data.base64EncodedString(),
                       sizeBytes: data.count, width: width, height: height)
    }
}
