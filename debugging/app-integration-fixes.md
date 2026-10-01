# App lifecycle and intent connection fixes

Date: 2026-10-01. Status: fixed and verified (unit level; see Actual fix for gaps). Parent review: [code-review-2026-10-01](code-review-2026-10-01.md). Depends on the B4 lifecycle half in [gateway-client-fixes](gateway-client-fixes.md).

Owned files:
- `FancyClaw/AppModel.swift`, `FancyClaw/ContentView.swift`, `FancyClaw/Onboarding/**`, `FancyClaw/SystemIntegration/**`
- `Packages/FancyClawKit/Sources/SystemIntegration/**` and its tests
- `FancyClawUITests/**`

Don't edit ChatCore or GatewayClient sources.

## Summary

### B3 — Warm-launch intents throw "not connected"
`AppModel.requireIntentConnection` awaits `prepare()`, which returns immediately once the initial prepare task has finished, then requires `status == .connected`. Backgrounding disconnects the socket (`ConnectionLifecycle.reconcileAvailability`). When the system foregrounds the app for Ask, New Chat, or the Control Center New Chat control, recovery has only just been scheduled. The intent throws `IntentError.notConnected`. Only cold launches work, so the Control almost always fails.

### B4 (app half) — Unordered scene-phase tasks
`ContentView` starts an independent `Task` per `scenePhase` change. `AppModel.setForeground(false)` sets `isForeground` and then awaits `runActivities?.connectionDidDisconnect()` (an ActivityKit delivery) before calling `lifecycle.setForeground(false)`. A following `true` task can reach the lifecycle first. The stale `false` then disconnects a visible app and leaves the lifecycle's `foreground` false, so only a manual Reconnect recovers.

### B5 — Disconnect keeps `initialProfile`
`AppModel.disconnect()` deletes the saved profile but never clears `initialProfile`. `ContentView` passes it to `OnboardingView`, whose `.task` then:
- pre-fills the forgotten URL, token and password,
- sets `usesEphemeralIdentity = true`, and
- disables Bonjour discovery.

A following manual connect uses `persist: false`, so it pairs a throwaway identity and saves nothing. Shortcuts entities and Live Activity URLs then fail, and the next launch returns to onboarding.

## Suggested triage

Write each regression test first and confirm it fails; then fix.

- **B3 plan:**
  - Add a small `@MainActor` helper in `SystemIntegration` (for example `ConnectionWaiter`) that takes a status-reading closure or `AsyncStream`, a timeout, and an injected `GatewayTiming`/clock. It returns when the status is `.connected`, throws on timeout, and throws immediately when no profile is configured.
  - `requireIntentConnection` should ensure foreground (`setForeground(true)` if needed), then wait up to about 10 s for connection before throwing `notConnected`.
  - Keep Ask's separate 25-second reply wait unchanged.
  **B3 tests:**
  - Swift Testing: feed `.offline` → `.reconnecting` → `.connected` and expect success; feed only `.reconnecting` and expect a timeout error under the injected clock.
  - UI test if practical: `-DemoConversation`, background the app (`XCUIDevice.shared.press(.home)`), invoke New Chat through the URL or intent path, and assert a new empty chat with no "Connection issue" alert.
- **B4 plan:**
  - Serialize foreground transitions in `AppModel`. Keep a monotonically increasing token, or a single chained task, so the latest value always wins.
  - Call `lifecycle.setForeground(value)` *before* awaiting Live Activity work.
  - After any await, skip stale transitions whose value no longer matches `isForeground`.
  - Keep `ContentView`'s call simple.
  **B4 test:** If a seam is reasonable, extract the ordering logic into a testable type, inject a suspending `RunActivityDriver`, call `false` then `true` concurrently, release, and expect lifecycle foreground and connected. Otherwise, cover it via the GatewayClient lifecycle test plus a UI test that backgrounds and quickly re-activates `-DemoSystemIntegration` and asserts the connection returns.
- **B5 plan:**
  - In `disconnect()`, set `initialProfile = nil` when `!isTestMode`. Debug FakeGateway onboarding still needs its ephemeral endpoint, so preserve test-mode behavior.
  - Confirm `OnboardingView` resets its pre-filled fields when `initialProfile` becomes nil.
  **B5 test:**
  - If a UI seam is needed, add a `#if DEBUG` launch argument that seeds a *saved* profile pointing at FakeGateway with `isTestMode` false semantics. Otherwise, extract and unit-test the disconnect state.
  - Expect empty URL and token fields and discovery enabled after Disconnect.

Verify by running `SystemIntegrationTests` plus the affected UI tests, then build the app and embedded extension. Check light, dark and Dynamic Type for any visible change.

## Actual fix

- **B3:** Added `ConnectionWaiter` (`@MainActor`, `SystemIntegration`): polls the status with an injected sleep (`GatewayTiming`), returns on `.connected`, throws `IntentError.notConnected` at once with no configured connection, and after 10 s of waiting. `AppModel.requireIntentConnection` now foregrounds if needed and uses it; Ask's 25 s reply wait is unchanged. Tests (`ConnectionWaiterTests`): reconnect-then-connected succeeds, reconnecting-only times out (100 polls), no connection fails with no sleep.
- **B4 (app half):** Added `ForegroundCoordinator` (`SystemIntegration`). `AppModel.setForeground` goes through it: the latest value wins, `lifecycle.setForeground` is called synchronously before any Live Activity await, and background activity cleanup is skipped when the app is foreground again. Test: `latestForegroundValueReachesLifecycleBeforeActivityWork` (background cleanup suspended; lifecycle must already see `[false, true]`).
- **B5:** `AppModel.disconnect()` sets `initialProfile = nil` outside test mode, so a new `OnboardingView` starts with empty fields, a persistent identity and Bonjour discovery. Test-mode (FakeGateway) onboarding is untouched.
- **Fail-before caveat:** the new helper types did not exist, so the regression tests failed to compile before the fix rather than failing on assertions. B5 and the `AppModel` wiring have no automated test: a UI test needs a debug seam seeding a saved profile with non-test-mode semantics; I judged that too invasive. Gap: B5 and the warm-launch UI path are unverified on screen.
- **Verification:** `SystemIntegrationTests` 18 passed. Full plan (iPhone 18 Pro, iOS 27.0): 229 discovered, 227 passed, 2 failed, both `PolishTests` contrast audits (`testChatAndDrawerAccessibility`, `testRichOutputAccessibilityAndLargeText`; elements: 'Notes.txt' attachment chip and rich-output text). They fail identically with my changes stashed (re-run of `testRichOutputAccessibilityAndLargeText` at HEAD), so they come from the earlier fix packages, not this one.

