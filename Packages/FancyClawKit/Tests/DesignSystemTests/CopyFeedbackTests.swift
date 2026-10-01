import Testing
@testable import DesignSystem

struct CopyFeedbackTests {
    @Test func copyShowsConfirmationAndAdvancesTrigger() {
        var feedback = CopyFeedback()
        #expect(!feedback.isCopied)
        feedback.recordCopy()
        #expect(feedback.isCopied)
        #expect(feedback.copyCount == 1)
    }

    @Test func resetClearsConfirmation() {
        var feedback = CopyFeedback()
        feedback.recordCopy()
        feedback.reset(afterCopy: 1)
        #expect(!feedback.isCopied)
    }

    @Test func repeatedCopiesAdvanceTheTriggerEvenWhileShowingCopied() {
        var feedback = CopyFeedback()
        feedback.recordCopy()
        feedback.recordCopy()
        #expect(feedback.copyCount == 2)
        #expect(feedback.isCopied)
    }

    @Test func staleResetDoesNotClearANewerCopy() {
        var feedback = CopyFeedback()
        feedback.recordCopy()
        feedback.recordCopy()
        feedback.reset(afterCopy: 1)
        #expect(feedback.isCopied)
        feedback.reset(afterCopy: 2)
        #expect(!feedback.isCopied)
    }
}
