import CryptoKit
import Foundation
import GatewayProtocol

public struct DeviceIdentity: Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey

    public init(rawPrivateKey: Data) throws {
        privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivateKey)
    }

    public static func generate() -> DeviceIdentity {
        DeviceIdentity(privateKey: Curve25519.Signing.PrivateKey())
    }

    private init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    public var rawPrivateKey: Data { privateKey.rawRepresentation }
    public var publicKey: Data { privateKey.publicKey.rawRepresentation }
    public var deviceID: String {
        SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()
    }

    public static func signaturePayload(
        deviceID: String, clientID: GatewayClientID = .iOSApp, mode: GatewayClientMode = .ui,
        role: GatewayRole = .operator, scopes: [OperatorScope], signedAt: Int,
        token: String, nonce: String, platform: String = "ios", deviceFamily: String = "iPhone"
    ) -> String {
        ["v3", deviceID, clientID.rawValue, mode.rawValue, role.rawValue,
         scopes.map(\.rawValue).joined(separator: ","), String(signedAt), token, nonce,
         platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
         deviceFamily.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
            .joined(separator: "|")
    }

    public func proof(
        challenge: ConnectChallenge, scopes: [OperatorScope], token: String,
        platform: String = "ios", deviceFamily: String = "iPhone"
    ) throws -> DeviceProof {
        let payload = Self.signaturePayload(
            deviceID: deviceID, scopes: scopes, signedAt: challenge.ts, token: token,
            nonce: challenge.nonce, platform: platform, deviceFamily: deviceFamily)
        let signature = try privateKey.signature(for: Data(payload.utf8))
        return DeviceProof(id: deviceID, publicKey: Base64URL.encode(publicKey),
                           signature: Base64URL.encode(signature), signedAt: challenge.ts,
                           nonce: challenge.nonce)
    }
}
