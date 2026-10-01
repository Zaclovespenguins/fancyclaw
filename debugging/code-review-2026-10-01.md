# Code review findings, October 2026

Date: 2026-10-01. Status: all 17 findings fixed and simulator-verified (iPhone 18 Pro / iOS 27.0); two pre-existing PolishTests contrast failures remain open, and the B3/B5 on-screen paths are unverified.

## Summary

A read-only correctness review covered all of `FancyClaw/`, `FancyClawWidgets/`, and every `FancyClawKit` module, plus the test plan, schema script and config. Each finding below was traced through the code and re-checked against the source before being recorded. These are code-reading observations; none has yet been reproduced by a failing test. The regression tests in the plan notes are meant to supply that evidence.

The following were checked and found correct: test-plan membership for all seven package targets, `PINNED_RELEASE`/`ProtocolVersion.pinnedRelease` agreement, the Bonjour type and usage strings, pending-RPC single resumption, handshake signing, backoff caps, `StreamingThrottle` trailing flush, `ApprovalStore` resolve/expiry races, `TranscriptCache` Gateway scoping, the Live Activity reducer, URL routing validation, and `#if DEBUG` containment of demo modes.

| ID | Severity | Defect | Location | Plan note |
| --- | --- | --- | --- | --- |
| B1 | High | A `final` with `yielded: true` marks the run terminal in the transcript store; later deltas and the real final are dropped and Stop can stick | `ConversationStore.swift` `receive` (`.final` case) | [chat-core-fixes](chat-core-fixes.md) |
| B2 | High | A failed `chat.send` leaves a normal-looking bubble, and the outbox is never resent; the disconnect banner promises otherwise | `ConversationStore.swift` `submit`, `connectionDidDisconnect` | [chat-core-fixes](chat-core-fixes.md) |
| B3 | High | Ask/New Chat intents and the Control throw `notConnected` on warm launch, because `requireIntentConnection` checks status before foreground recovery finishes | `AppModel.swift` `requireIntentConnection` | [app-integration-fixes](app-integration-fixes.md) |
| B4 | High | A quick background/foreground cycle can leave a visible app settled `.offline`: lifecycle reentrancy across `await connection.disconnect()`, plus unordered scene-phase `Task`s in the app | `ConnectionLifecycle.swift` `reconcileAvailability`; `AppModel.setForeground`; `ContentView` `onChange(of: scenePhase)` | [gateway-client-fixes](gateway-client-fixes.md), [app-integration-fixes](app-integration-fixes.md) |
| B5 | Medium | Disconnect/Forget keeps `initialProfile`, so onboarding pre-fills the old credentials, disables discovery and connects with an ephemeral, unsaved identity | `AppModel.disconnect`; `OnboardingView` `.task` | [app-integration-fixes](app-integration-fixes.md) |
| B6 | Medium | After a startup-unavailable retry sleep, a stale connect attempt overwrites the live `socket` and wedges every later RPC | `GatewayConnection.connect` retry loop | [gateway-client-fixes](gateway-client-fixes.md) |
| B7 | Medium | A history refresh during streaming always loses the revision check and immediately re-requests, issuing back-to-back `chat.history` calls for the length of the stream | `ConversationStore.refreshHistory`/`finishLoadingHistory` | [chat-core-fixes](chat-core-fixes.md) |
| B8 | Medium | A streamed row `"R:assistant"` and a history entry without `entryId` (`"R:assistant:"`) both survive reconcile, so the reply shows twice | `ConversationStore.reconcileHistory`; `ChatMessageIdentity.historyIdentity` | [chat-core-fixes](chat-core-fixes.md) |
| B9 | Medium | Concurrent `start()` calls both pass `eventTask == nil` before the `await`; one subscription leaks and survives `stopListening()`/`invalidate()` | `ConversationStore.start` | [chat-core-fixes](chat-core-fixes.md) |
| B10 | Low | A Keychain save failure after `ready = true` turns a successful handshake into an error and leaves the media origin and bearer set; recovery then loops | `GatewayConnection.connect` | [gateway-client-fixes](gateway-client-fixes.md) |
| B11 | Low | Per-RPC timeout tasks are never cancelled, and caller cancellation is ignored for up to 15 s | `GatewayConnection.request` | [gateway-client-fixes](gateway-client-fixes.md) |
| B12 | Low | Pairing retry clips its last sleep to the deadline, then throws without the final attempt | `PairingCoordinator.connect`; `PairingRetrySchedule.delay` | [gateway-client-fixes](gateway-client-fixes.md) |
| B13 | Low | The code-block “Copied” state never resets; later copies give no haptic or visible confirmation | `MarkdownCodeBlock.copy()` | [design-and-test-support-fixes](design-and-test-support-fixes.md) |
| B14 | Low | FakeGateway sends the seq-1 delta after an abort | `FakeGateway` `chat.send` task | [design-and-test-support-fixes](design-and-test-support-fixes.md) |
| B15 | Low | `FakeGateway.start()` can resume its continuation twice (trap), and hangs if stopped before ready | `FakeGateway.start` | [design-and-test-support-fixes](design-and-test-support-fixes.md) |
| B16 | Low | A FakeGateway request decode error ends that connection's receive loop silently | `FakeGateway.receiveRequest` | [design-and-test-support-fixes](design-and-test-support-fixes.md) |
| B17 | Low | The schema checker ignores `maximum`, `maxItems`, `pattern`, `allOf`/`not` and `oneOf`, so strict-encoding tests can pass vacuously on bounds | `TestSupport/ProtocolSchema.swift` | [design-and-test-support-fixes](design-and-test-support-fixes.md) |

Noted but not filed as defects:
- A malformed *known* event still fails the read loop. This is a recorded deliberate choice (Post-slice fix in the deviations log), although it is in tension with tolerant decoding.
- The cache key is `profile.url.absoluteString`, so a trailing-slash or host-case change splits one Gateway's cache.
- `pendingAssistantMessages` is keyed by run, which may mix rows when one run emits two assistant entries. Its confidence is lower; recheck while fixing B8.

## Suggested triage

Fixes are grouped into four work packages, each owning disjoint files: ChatCore, GatewayClient, app/system integration, and DesignSystem/TestSupport. Each package note records its plan and the regression tests that must fail before the fix and pass after it. Packages run one after another so that Xcode builds and test runs don't collide in a shared worktree. Run the full `FancyClaw` test plan once after all four.

## Actual fix

All four packages are implemented; each package note's **Actual fix** has per-bug details and test evidence. Commits:
- `0147a01`: DesignSystem/TestSupport.
- `77a5bd8`: GatewayClient.
- `dc001da` and `4d62d2d`: ChatCore. The second commit followed coordinator review: raced snapshots no longer overwrite live run state, and only transport failures auto-resend.
- `b9d127d`: app/intents.
- `4841062`: per-message Retry, so the button also works for Gateway-rejected sends.

Full test plan after `b9d127d`: **229 discovered, 227 passed, 2 failed, 0 skipped**. `4841062` changed only ChatCore/ChatView, and its ChatCoreTests pass 69/69. The failures are `PolishTests/testChatAndDrawerAccessibility` and `PolishTests/testRichOutputAccessibilityAndLargeText`, both “Contrast failed” at `PolishTests.swift:120`. The failing elements are the `Notes.txt` attachment chip and rich-output text.

These failures **predate this review**. Both tests fail at `c8973d2`, the pre-review HEAD, and pass at `254ff43`. Between those, `688ddec` touched only an import and `#Preview` code, which UI tests don't run. So `c8973d2` (“compact controls” font and padding changes in `ChatComposer.swift`, never run against the suite) is the likely cause. This is inferred, not confirmed by running at `688ddec`. Their fixes are left to the owner.

Remaining gaps:
- B3 (warm-launch intents) and B5 (forget Gateway) have unit-level coverage only; no UI test exercises them.
- The B15 double-resume trap and the B13 on-screen label reset have no dedicated test.
- Several fail-before checks for new helper APIs were compile failures, not assertion failures.

Logs: `~/Library/Developer/XcodeBuildMCP/workspaces/bridge-cse_01SdtXZEdp6nPTp5oDqbrKhy-3a39498a758d/logs/`. Full suite: `test_sim_2026-10-01T20-14-25-489Z_pid39798_1b368b34.log`. Bracket runs: `…20-26-44-996Z…f51f0109.log` (`c8973d2`) and `…20-27-49-551Z…836bfaba.log` (`254ff43`).
