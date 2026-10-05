# Onboarding page selection mismatch

Date: 2026-10-04. Status: fixed; simulator verification passed.

## Summary

The R5 full plan failed `SettingsTests/testReconnectAndDisconnect()` after successful reconnection and disconnect. The app left the tab shell, but the expected manual connection form was absent. Its failure hierarchy showed the onboarding welcome content with the real “Set up connection” button. After following that button in an unchanged app rerun, the test again found no `onboarding.connect` after ten seconds. That second hierarchy still showed welcome content while the native page indicator reported “page 2 of 3.”

Observed hierarchies: `/private/tmp/fancyclaw-r5-settings-failure/4FE736F8-91DE-4130-A30B-45741262915C.txt` and `/private/tmp/fancyclaw-r5-settings-rerun/C17DDE4A-C7A6-45BF-A7BD-76572937D6A9.txt`. Rerun bundle: `/Volumes/SSDCache/Xcode/DerivedData/FancyClaw-bypnjtyvdvflnmctxqlpgdlhnibo/Logs/Test/Test-FancyClaw-2026.10.04_18-27-05--0600.xcresult`.

Source observations: `OnboardingModel.selectedPage` originally began at 0. `OnboardingView.task` then filled the initial profile and set page 1 after the paged TabView's first render. Test-mode disconnect retains `initialProfile`; ordinary disconnect clears it. The welcome button also sets page 1. Existing `-FakeGateway` UI coverage expects the initial manual form directly, while `-OnboardingPreview` starts on welcome and advances by tapping setup.

Inference: changing selection during native page-controller initialization allowed the selection/indicator to advance without replacing the visible welcome page. A welcome-button tap that writes the already-selected page cannot recover that mismatch. The two captures and repeated missing form support a functional initialization issue rather than merely a slow assertion. The proposed correction still needs simulator verification; no definitive framework-internal diagnosis is claimed.

## Suggested triage

Build with the official Xcode MCP server, then run Settings reconnect/disconnect, `ChatTests/testSendShowsFakeGatewayReply()` (initial profile), `PolishTests/testOnboardingErrorRecovery()` (nil profile), and the XXL onboarding steps in `PolishTests/testLargeTextDarkMode()`. Retain the no-tab-bar and final `onboarding.connect` assertions. Inspect any repeat failure's page indicator/content pair and ensure supplied profiles still prefill URL/token/password with ephemeral identity. Confirm normal nil-profile welcome behavior remains unchanged.

## Actual fix

`OnboardingView` now creates its state model from `initialProfile` in its initializer. The model prepares URL/token/password, ephemeral identity and selected page before the first paged TabView render. Its task only installs the connection callback; it no longer mutates initial selection afterward. The Settings test follows either actual welcome or the manual form and still requires the final Connect control. Root verified an official app/extension/test-target build with zero errors and all four focused onboarding/Settings checks passed (4/4, no skips). Build log: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261004-183111.txt`; test summary: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/RunSomeTests/8F59AEF6-17F6-4B98-B779-1E0890FEAFCC.txt`.
