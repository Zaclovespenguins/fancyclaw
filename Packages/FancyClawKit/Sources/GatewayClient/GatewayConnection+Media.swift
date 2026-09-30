import Foundation
import GatewayProtocol

extension GatewayConnection {
    /// Resolves artifact IDs afresh; capability URLs may expire between launches.
    public func imageData(sessionKey: String, media: ContentBlock.Media) async throws -> Data {
        if let artifactID = media.artifactId {
            let download: JSONValue = try await request("artifacts.download", params: JSONValue.object([
                "sessionKey": .string(sessionKey), "artifactId": .string(artifactID)
            ]), returning: JSONValue.self)
            if let encoded = download["data"]?.stringValue, let bytes = Data(base64Encoded: encoded) {
                guard bytes.count <= 25 * 1024 * 1024 else { throw ConnectionError.frameTooLarge }
                return bytes
            }
            guard let reference = download["url"]?.stringValue else { throw URLError(.resourceUnavailable) }
            return try await fetchImage(reference)
        }
        guard let reference = media.url else { throw URLError(.resourceUnavailable) }
        return try await fetchImage(reference)
    }
}
