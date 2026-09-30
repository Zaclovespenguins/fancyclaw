import Foundation

extension RunActivityAttributes {
    public var sessionURL: URL? {
        var components = URLComponents()
        components.scheme = "fancyclaw"
        components.host = "session"
        components.queryItems = [URLQueryItem(name: "key", value: sessionKey)]
        return components.url
    }

    public static func sessionKey(from url: URL) -> String? {
        guard url.scheme == "fancyclaw", url.host == "session", url.path.isEmpty,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 1, items[0].name == "key", let key = items[0].value, !key.isEmpty else { return nil }
        return key
    }
}
