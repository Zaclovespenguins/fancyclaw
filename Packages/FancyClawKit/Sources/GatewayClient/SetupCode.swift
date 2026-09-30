import Foundation

public enum SetupCodeError: Error, Equatable, Sendable {
    case malformed
    case expired
    case missingURL
}

/// Decoded `openclaw qr` payload. Both `{url: ...}` and `{host, port, tls}` forms are accepted.
public struct SetupCode: Codable, Hashable, Sendable {
    public var profile: GatewayProfile
    public var urls: [URL]
    public var expiresAtMs: Int64?

    public init(profile: GatewayProfile, urls: [URL] = [], expiresAtMs: Int64? = nil) {
        self.profile = profile
        self.urls = urls
        self.expiresAtMs = expiresAtMs
    }

    public static func parse(_ value: String, now: Date = .now) throws -> SetupCode {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded: String
        if let data = Data(base64Encoded: trimmed) { encoded = trimmed; _ = data }
        else if let data = Base64URL.decode(trimmed) { _ = data; encoded = trimmed }
        else { throw SetupCodeError.malformed }
        guard let data = Base64URL.decode(encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SetupCodeError.malformed }
        let root = object["url"] as? String
        let host = object["host"] as? String
        let url: URL?
        if let root { url = URL(string: root) }
        else if let host {
            let tls = object["tls"] as? Bool ?? false
            var components = URLComponents()
            components.scheme = tls ? "wss" : "ws"
            components.host = host
            components.port = object["port"] as? Int ?? 18789
            components.path = object["contextPath"] as? String ?? "/"
            url = components.url
        } else { url = nil }
        guard let url, let host = url.host, !host.isEmpty else { throw SetupCodeError.missingURL }
        guard ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
              url.port.map({ (1...65_535).contains($0) }) ?? true else { throw SetupCodeError.malformed }
        let expires = (object["expiresAtMs"] as? NSNumber)?.int64Value
        if let expires, expires <= Int64(now.timeIntervalSince1970 * 1000) { throw SetupCodeError.expired }
        let alternatives = (object["urls"] as? [String] ?? []).compactMap(URL.init(string:)).filter {
            guard let host = $0.host, !host.isEmpty, ["ws", "wss"].contains($0.scheme?.lowercased() ?? "") else { return false }
            return $0.port.map { (1...65_535).contains($0) } ?? true
        }
        let profile = GatewayProfile(url: url, token: object["token"] as? String,
            bootstrapToken: object["bootstrapToken"] as? String, password: object["password"] as? String,
            tlsFingerprint: object["tlsFingerprint"] as? String)
        return SetupCode(profile: profile, urls: alternatives, expiresAtMs: expires)
    }
}
