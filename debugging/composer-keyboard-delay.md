# Composer keyboard delay

Date: 2026-09-30
Status: Verified on physical device by owner

## Summary

The owner reports needing several taps on “Message FancyClaw” before the keyboard appears on a physical iPhone. Official Xcode MCP `RunProject(attachDebugger: true)` built and launched FancyClaw successfully on Zachary’s iPhone (iOS 27.2), PID 1856, launch reference `c7dd10a80`, without build errors.

Observed console output (local Mountain time):
- 19:03:12: five `onChange(of: AnyTextLayoutCollection) action tried to update multiple times per frame` warnings.
- 19:03:21: `Gesture: System gesture gate timed out`.
- 19:03:30 and 19:03:38: keyboard prediction-cell constraint conflicts (`TUIPredictionViewCell` width zero); UIKit breaks internal constraints to recover.
- Through 19:03:42: 815 keyboard render-factory property warnings (163 each for five properties), plus Core Animation handler warnings.

These observations show gesture/keyboard/layout diagnostics in the phone launch, but do not establish causality or identify which tap first reached the text field. User timing/tap-count correlation remains pending. The debugger confirmed the process remained running.

Code inspection: `ChatComposer` uses a multiline `TextField` with `lineLimit(1...5)`, no explicit minimum touch height or focus binding, inside a taller padded HStack with 44-point attachment/send controls and interactive glass. A small empty-field touch region is a hypothesis, not a confirmed cause. The keyboard constraint warnings originate in Apple's prediction views; there is no evidence that app code created those constraints.

Build log: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/0CD6BB2F-DE3A-4052-ABAB-276202884B46/RunProject/RunProject-Log-20260930-190239.txt`.

## Suggested triage

The owner confirmed that tapping exactly on the placeholder works. Implemented an explicit focus binding, a 44-point minimum field height, and a composer background tap handler that requests field focus without replacing attachment/send actions. Removed interactive behavior from the decorative glass. Reduced row spacing and padding, plus the attachment symbol size and Send/Stop visible circle (32 points), retaining 44-point control touch regions.

Official Xcode MCP BuildProject succeeded without errors and RunProject launched the updated app on Zachary’s iPhone, PID 1882, launch reference `c7d3fde00`. Build log: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/0CD6BB2F-DE3A-4052-ABAB-276202884B46/BuildProject/BuildProject-Log-20260930-190925.txt`. First-tap keyboard behavior and layout on the phone remain pending owner confirmation; compilation alone does not verify the fix.

Correlate the owner's first tap and keyboard appearance with the launch logs. If needed, add temporary privacy-safe focus and keyboard notification timing diagnostics, and sample the main-thread stack during a failed tap. Compare taps on the placeholder versus surrounding field space. Separately test a full-height field hit region and noninteractive glass to isolate touch routing; do not treat either as a verified fix until the phone responds reliably to one tap. Check cold and subsequent keyboard presentations.

## Actual fix

Added a focus binding and composer-background tap handler, enlarged the empty field to a 44-point minimum height, and made the decorative glass noninteractive. Reduced padding, spacing, and visible button sizes while retaining 44-point touch targets. The owner confirmed first-tap keyboard presentation, then reported a 2–3 second delay under the attached debugger.

Added privacy-safe OSLog timing for focus and keyboard will/did-show notifications and relaunched without the debugger. Official Xcode MCP BuildProject passed without errors; RunProject launched PID 1893, reference `c7d3ff780`. At 19:12:51.026773 focus became true, will-show arrived at 19:12:51.040465 (about 14 ms), and did-show at 19:12:51.443783 (about 417 ms after focus). A subsequent focus at 19:13:28.002842 likewise reached will-show in 13 ms and did-show in 418 ms. One intervening background tap occurred while focus was already true and cannot establish a fresh focus-to-keyboard delay. The owner then reported that the issue appears fixed. The attached-debugger delay's cause remains unproven; the latest measured presentations were normal without it. `git diff --check` passed.

Final build log: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/0CD6BB2F-DE3A-4052-ABAB-276202884B46/BuildProject/BuildProject-Log-20260930-191212.txt`.
