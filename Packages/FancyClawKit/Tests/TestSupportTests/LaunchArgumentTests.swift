import Testing
@testable import TestSupport

struct LaunchArgumentTests {
    @Test(arguments: LaunchArgument.allCases)
    func argumentsUseDashPrefix(_ argument: LaunchArgument) {
        #expect(argument.rawValue.hasPrefix("-"))
    }
}
