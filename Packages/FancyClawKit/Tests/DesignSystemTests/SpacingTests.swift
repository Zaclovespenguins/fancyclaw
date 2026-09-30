import Testing
@testable import DesignSystem

struct SpacingTests {
    @Test func scaleIsIncreasing() {
        let scale = [Spacing.xSmall, Spacing.small, Spacing.medium, Spacing.large, Spacing.xLarge]
        #expect(scale == scale.sorted())
    }
}
