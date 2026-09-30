import Testing
@testable import GatewayClient

struct GatewayDefaultsTests {
    @Test func defaultPortAndServiceType() {
        #expect(GatewayDefaults.port == 18789)
        #expect(GatewayDefaults.bonjourServiceType == "_openclaw-gw._tcp")
    }
}
