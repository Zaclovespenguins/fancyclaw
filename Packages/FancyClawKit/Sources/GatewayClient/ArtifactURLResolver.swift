import Foundation

public enum ArtifactURLResolver {
    /// Converts the WebSocket origin to HTTP, retaining a reverse proxy's context path.
    public static func baseURL(for gateway: URL) throws -> URL {
        var components = URLComponents(url: gateway, resolvingAgainstBaseURL: true)
        switch components?.scheme {
        case "wss": components?.scheme = "https"
        case "ws": components?.scheme = "http"
        case "http", "https": break
        default: throw URLError(.badURL)
        }
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        if components?.path.hasSuffix("/") == false { components?.path += "/" }
        guard let url = components?.url, url.host != nil else { throw URLError(.badURL) }
        return url
    }

    public static func resolve(_ reference: String, gateway: URL) throws -> URL {
        let base = try baseURL(for: gateway)
        guard let url = URL(string: reference, relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme), url.host != nil,
              url.user == nil, url.password == nil else { throw URLError(.badURL) }
        // Apply the same cleartext restrictions as the WebSocket transport.
        var socket = URLComponents(url: url, resolvingAgainstBaseURL: true)
        socket?.scheme = url.scheme == "https" ? "wss" : "ws"
        guard let socketURL = socket?.url else { throw URLError(.badURL) }
        try TransportPolicy.validate(socketURL)
        // Gateway-generated API references omit the reverse proxy's context path.
        if base.path != "/", url.path.hasPrefix("/api/"), isSameOrigin(url, gateway: gateway) {
            guard var scoped = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  let baseComponents = URLComponents(url: base, resolvingAgainstBaseURL: true) else { throw URLError(.badURL) }
            let prefixedPath = String(baseComponents.percentEncodedPath.dropLast()) + scoped.percentEncodedPath
            scoped.percentEncodedPath = prefixedPath
            guard let scopedURL = scoped.url else { throw URLError(.badURL) }
            return scopedURL
        }
        return url
    }

    public static func isSameOrigin(_ url: URL, gateway: URL) -> Bool {
        guard let base = try? baseURL(for: gateway) else { return false }
        func port(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
        return url.scheme == base.scheme && url.host?.lowercased() == base.host?.lowercased()
            && port(url) == port(base)
    }
}
