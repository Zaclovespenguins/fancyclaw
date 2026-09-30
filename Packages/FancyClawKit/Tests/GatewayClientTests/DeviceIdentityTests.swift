import Foundation
import GatewayClient
import GatewayProtocol
import Testing

@Suite("Device identity")
struct DeviceIdentityTests {
    @Test func knownVector() throws {
        let seed = Data([0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60,
                         0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
                         0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19,
                         0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60])
        let identity = try DeviceIdentity(rawPrivateKey: seed)
        #expect(identity.deviceID == "21fe31dfa154a261626bf854046fd2271b7bed4b6abe45aa58877ef47f9721b9")
        let payload = DeviceIdentity.signaturePayload(deviceID: "device", scopes: [.read, .write, .approvals],
            signedAt: 123, token: "test-token", nonce: "nonce", platform: " IOS ", deviceFamily: " iPhone ")
        #expect(payload == "v3|device|openclaw-ios|ui|operator|operator.read,operator.write,operator.approvals|123|test-token|nonce|ios|iphone")
        let proof = try identity.proof(challenge: .init(nonce: "nonce", ts: 123),
                                       scopes: [.read, .write, .approvals], token: "test-token")
        #expect(Base64URL.decode(proof.publicKey) == identity.publicKey)
        #expect(Base64URL.decode(proof.signature)?.count == 64)
    }
}
