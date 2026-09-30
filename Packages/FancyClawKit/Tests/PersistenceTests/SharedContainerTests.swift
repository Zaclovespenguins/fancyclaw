import Testing
@testable import Persistence

struct SharedContainerTests {
    @Test func appGroupMatchesEntitlements() {
        #expect(SharedContainer.appGroupIdentifier == "group.com.zacisnotacompany.fancyclaw")
    }
}
