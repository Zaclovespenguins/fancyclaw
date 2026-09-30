import Foundation
import Darwin

public enum TransportPolicyError: Error, Equatable, Sendable {
    case missingHost
    case unsupportedScheme(String?)
    case insecurePublicHost(String)
}

public enum TransportPolicy {
    /// Allows cleartext WebSockets only on local, private, or Tailscale addresses.
    public static func validate(_ url: URL) throws {
        guard let host = url.host?.lowercased(), !host.isEmpty else { throw TransportPolicyError.missingHost }
        switch url.scheme?.lowercased() {
        case "wss": return
        case "ws":
            guard isPrivateHost(host) else { throw TransportPolicyError.insecurePublicHost(host) }
        default: throw TransportPolicyError.unsupportedScheme(url.scheme)
        }
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".ts.net") { return true }
        if let bytes = ipv6Bytes(host) {
            let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            return isLoopback || (bytes[0] & 0xfe == 0xfc) || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
        }
        var ipv4 = in_addr()
        let isIPv4 = host.withCString { inet_pton(AF_INET, $0, &ipv4) }
        guard isIPv4 == 1 else { return false }
        let parts = withUnsafeBytes(of: ipv4) { Array($0) }
        let (a, b) = (parts[0], parts[1])
        return a == 10 || a == 127 || (a == 169 && b == 254) ||
            (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) ||
            (a == 100 && (64...127).contains(b))
    }

    private static func ipv6Bytes(_ host: String) -> [UInt8]? {
        let literal = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        var address = in6_addr()
        let result = literal.withCString { inet_pton(AF_INET6, $0, &address) }
        guard result == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0) }
    }
}
