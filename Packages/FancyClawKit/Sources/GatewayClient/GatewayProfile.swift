import Foundation
import Security

/// Credentials and transport hints for one Gateway.
public struct GatewayProfile: Codable, Hashable, Sendable {
    public var url: URL
    public var token: String?
    public var bootstrapToken: String?
    public var password: String?
    public var tlsFingerprint: String?

    public init(url: URL, token: String? = nil, bootstrapToken: String? = nil,
                password: String? = nil, tlsFingerprint: String? = nil) {
        self.url = url
        self.token = token
        self.bootstrapToken = bootstrapToken
        self.password = password
        self.tlsFingerprint = tlsFingerprint
    }
}

/// Stores the selected Gateway profile in this device's Keychain.
public struct GatewayProfileStore: Sendable {
    private let service: String
    private let account = "gateway-profile"

    public init(service: String = "com.zacisnotacompany.fancyclaw.gateway") { self.service = service }

    public func load() throws -> GatewayProfile? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        return try JSONDecoder().decode(GatewayProfile.self, from: data)
    }

    public func save(_ profile: GatewayProfile) throws {
        let data = try JSONEncoder().encode(profile)
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let value: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemAdd(key.merging(value) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(key as CFDictionary, value as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError(updateStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status)
        }
    }

    public func delete() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }
}
