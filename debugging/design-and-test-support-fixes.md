# Design system and test support fixes

Date: 2026-10-01. Status: planned; not yet implemented. Parent review: [code-review-2026-10-01](code-review-2026-10-01.md).

Owned files: `Packages/FancyClawKit/Sources/DesignSystem/**`, `Packages/FancyClawKit/Sources/TestSupport/**`, and their test targets (`DesignSystemTests`, `TestSupportTests`). FakeGateway changes must keep existing tests passing; other packages depend on its behavior.

## Summary

### B13 — The code-block "Copied" state never resets
`MarkdownCodeBlock.copy()` sets `copied = true`, and nothing resets it. After the first tap the button shows "Copied" for the life of the view. VoiceOver keeps announcing it, and later copies give no haptic, because the `sensoryFeedback` trigger value no longer changes.

### B14 — FakeGateway sends a delta after an abort
The `chat.send` reply task sends the seq-1 delta without checking `activeRuns`; only the final is guarded. Aborting within 150 ms produces `aborted` (seq 3) followed by a stray `delta` (seq 1), which a real Gateway wouldn't send. The store's sequence guard currently masks this, so tests can't catch a regression there.

### B15 — `FakeGateway.start()` continuation misuse
`stateUpdateHandler` is never cleared after the first resume. A later `.failed` (or a second `.ready`) resumes the `CheckedContinuation` again, which traps. `.cancelled` is ignored, so calling `stop()` before ready hangs `start()`. `listener` is also accessed outside `lock`.

### B16 — FakeGateway's receive loop dies on a decode error
In `receiveRequest`, a thrown decode (for example `ExecApprovalResolveParams`) lands in the outer `catch`, which records the failure but never re-arms `receiveRequest`. The connection then goes deaf, and the next RPC times out with a misleading error.

### B17 — The schema checker skips constraints
`ProtocolSchema` ignores `maximum`, `maxItems`, `pattern`, `allOf`, `not`, and treats `oneOf` as `anyOf`. When both are present, only `anyOf` is checked. Strict-encoding conformance tests can therefore pass vacuously, for example on `ChatHistoryParams.limit > 1000`, `mentions` > 10, `ttlMinutes` > 120, or the `ModelsListParams` exclusion.

## Suggested triage

Write each regression test first and confirm it fails; then fix.

- **B13 plan:** Reset `copied` after about 2 s with a cancellable `.task(id:)`, or restart a stored task on each tap so rapid taps re-trigger feedback. Keep haptics gated by `hapticsEnabled`.
  **B13 test:** If the reset logic can be factored into a small testable value or helper, unit-test it in `DesignSystemTests`. Otherwise add a UI assertion in an existing rich-output UI test: tap `markdown.copyCode`, see "Copied", wait, and see the "Copy code" label return.
- **B14 plan:** Guard the delta send with `activeRuns[runID] != nil` under `lock`.
  **B14 test:** In `TestSupportTests`, connect a `GatewayConnection` to FakeGateway, send, abort immediately, collect events for 400 ms, and expect no chat event after `aborted`.
- **B15 plan:**
  - Resume exactly once: use a lock-protected `resumed` flag, or nil the handler after resuming.
  - Map `.cancelled` before ready to a thrown error.
  - Protect `listener` with `lock`.
  **B15 test:** Call `start()` in a task, call `stop()` before it reports ready, and expect `start()` to throw within 1 s rather than hang. Add a second test: a normal start and stop with no crash.
- **B16 plan:** Catch per-request handling errors, record them in `failures`, reply with an `ok: false` error response for the request ID when possible, and always re-arm `receiveRequest`.
  **B16 test:** Send a malformed `exec.approval.resolve`, then `sessions.list` on the same connection. Expect an error response for the first, a reply for the second, and the failure to be recorded.
- **B17 plan:**
  - Implement `maximum`, `maxItems`, `pattern` (`NSRegularExpression`), `allOf`, `not`, and true `oneOf` (exactly one match), checking `anyOf`/`oneOf` independently.
  - Afterward, run the full protocol conformance tests; any newly exposed violation is a real encoding bug to report, not a reason to relax the checker.
  **B17 tests:**
  - `{"sessionKey":"k","limit":5000}` against `ChatHistoryParams` must violate.
  - An over-long `mentions` must violate.
  - The `ModelsListParams` mutual exclusion must violate.
  - Valid fixtures still pass.

Verify by running `DesignSystemTests`, `TestSupportTests`, and `GatewayProtocolTests` through the simulator test plan.

## Actual fix

