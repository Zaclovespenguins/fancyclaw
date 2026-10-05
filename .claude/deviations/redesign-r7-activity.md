# Redesign R7: Activity placeholder

Date: 2026-10-04. Plan: `layout_redesign.md`, Slice R7. Status: implemented and verified.

## Implementation

- Replaced the Activity tab's generic placeholder with `ActivityView`: a large-title Activity screen with a native Today/Scheduled segmented picker, ambient theme background, and `ContentUnavailableView` copy for each segment.
- Added `TimelineRow` as a preview-only component. It uses theme tokens, semantic text styles and scaled time/dot dimensions. It is not connected to Gateway data.
- Added `ActivityTests.testTodayAndScheduledPlaceholders` for the segment behavior and `testActivityScreenshotsBothSegmentsLightDarkDefaultAndXXL` for both segments across light/dark and default/XXL appearance (eight retained screenshots).
- Updated the redesign handoff status, app status/layout documentation, theme comments, and the deferred work notes to match the tracked `Design/openclaw-1b/` handoff and the shipped read-only Skills sheet / Activity placeholder.
- No accessibility audit or audit-driven repair was added. The owner-directed deferral is recorded in `redesign-accessibility-deferred.md`.

## Verification

- Root and a separate GPT 6 Luna reviewer inspected Activity, tab integration, functional tests and the documentation against R7 scope; no concrete remaining findings. Official app/extension/test-target build succeeded with **zero errors**: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261004-224011.txt`.
- Focused Activity segment behavior, eight-image screenshot matrix and existing Home/Settings/tab navigation passed **3/3, 0 failures, 0 skips**. Summary: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/RunSomeTests/50171D86-3A87-41AD-9CFE-65596CAF885D.txt`.
- Root reviewed all eight Activity screenshots: both segments in light/dark, default/XXL. Native selection state, exact placeholder copy, warm light/dark theme background and text reflow look correct. Contact sheet: `/private/tmp/fancyclaw-r7-activity-screens/matrix.jpg`. No live timeline or schedule data is shown.
- The final full `FancyClaw` test plan passed **349/349 unique tests, 0 failures, 0 skips**, on iPhone 18 Pro / iOS 27.0. Parameterized runs expanded to **499/499**. Package totals: GatewayProtocol 79, GatewayClient 36, ChatCore 131, Persistence 4, DesignSystem 14, TestSupport 12, SystemIntegration 34 (**310 Swift Testing tests**); app UI **39/39**, including both Activity tests and all five Skills tests. The corrected read/write/admin Skills scope gate is included in this run.
- Official result bundle: `/Volumes/SSDCache/Xcode/DerivedData/FancyClaw-bypnjtyvdvflnmctxqlpgdlhnibo/Logs/Test/Test-FancyClaw-2026.10.04_22-45-24--0600.xcresult`. The MCP request timed out at 300 seconds while Xcode continued; root waited for the bundle to finalize and inspected `xcresulttool get test-results summary` and `tests`. Test-tree export: `/private/tmp/fancyclaw-r7-full-tests.json`.
- Root exported and reviewed all **32 fresh screenshots** from that full run (eight each for Home, Chats, Skills, Activity). Light/dark backgrounds, default/XXL text reflow, native navigation/selection, Home approval/running/recent sections, Chats date groups/status chips, Skills grid/read-only detail, and both Activity placeholders match their implemented scope. Contact sheets: `/private/tmp/fancyclaw-r7-final-home/matrix.jpg`, `/private/tmp/fancyclaw-r7-final-chats/matrix.jpg`, `/private/tmp/fancyclaw-r7-final-skills/matrix.jpg`, `/private/tmp/fancyclaw-r7-final-activity/matrix.jpg`. A GPT 6 Luna reviewer and root also inspected the four original Skills grid images: the complete search placeholder is present; an apparent crop in the reduced montage did not require a code change.
- The result summary retains two native `_UIReparentingView` hierarchy warnings and one AppEnum `to-0.0` display-representation warning; no test failures resulted. These warnings were not changed by this placeholder slice. Accessibility-only audits remain deferred, and physical-device/live-Gateway behavior plus the iOS 26 deployment floor remain unverified as recorded in `CLAUDE.md`.
