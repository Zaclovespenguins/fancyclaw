import Foundation
import Security

public struct DeviceIdentityStore: Sendable {
    private let service: String

    public init(service: String = "com.zacisnotacompany.fancyclaw.device") {
        self.service = service
    }

    public func loadOrCreate() throws -> DeviceIdentity {
        if let bytes = try read(account: "ed25519") {
            return try DeviceIdentity(rawPrivateKey: bytes)
        }
        let identity = DeviceIdentity.generate()
        try write(identity.rawPrivateKey, account: "ed25519")
        return identity
    }

    public func deviceToken(deviceID: String, role: String) throws -> String? {
        guard let bytes = try read(account: "token.\(deviceID).\(role)") else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    public func saveDeviceToken(_ token: String, deviceID: String, role: String) throws {
        try write(Data(token.utf8), account: "token.\(deviceID).\(role)")
    }

    private func read(account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        return data
    }

    private func write(_ data: Data, account: String) throws {
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemAdd(key.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
            guard update == errSecSuccess else { throw KeychainError(update) }
        } else if status != errSecSuccess {
            throw KeychainError(status)
        }
    }
}

public struct KeychainError: Error, Sendable {
    public let status: OSStatus
    public init(_ status: OSStatus) { self.status = status }
}
