import Testing
@testable import GatewayProtocol

struct ProtocolVersionTests {
    @Test func pinsProtocolFour() {
        #expect(ProtocolVersion.current == 4)
        #expect(ProtocolVersion.pinnedRelease == "2026.9.6")
    }
}
