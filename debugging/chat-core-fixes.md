# ChatCore conversation store fixes

Date: 2026-10-01. Status: planned; not yet implemented. Parent review: [code-review-2026-10-01](code-review-2026-10-01.md).

Owned files: `Packages/FancyClawKit/Sources/ChatCore/**`, `Packages/FancyClawKit/Tests/ChatCoreTests/**`, and the message-row view in `FancyClaw/Chat/` (for B2's retry affordance only). Don't edit `AppModel.swift`, `GatewayClient`, or `TestSupport`; FakeGateway's existing `rpcErrors`/`queuedRPCReplies` seams are enough.

## Summary

### B1 — A yielded final terminates the run
In `ConversationStore.receive`, `.final(let final)` always sets `run.isTerminal = true`. `ChatEvent.Final.yielded` exists, and `ask()` and `RunActivityTracker` both treat `yielded == true` as "still running". After a yielded final the guard `!run.isTerminal` drops later deltas and the real final. The visible reply freezes at the yielded text, `isStreaming` goes false while the Gateway is still running, and the refresh triggered by the yielded final can set `hasActiveRun == true` with nothing left to clear it.

### B2 — A failed send looks delivered and is never resent
`submit` catches a `chat.send` error, sets `errorMessage`, and still returns `true`. The optimistic bubble looks normal, and its `PendingSend` stays in `outbox`, but nothing replays it: `retry(idempotencyKey:)` has no UI caller. Meanwhile `connectionDidDisconnect` says "Your message will remain here while the Gateway reconnects", and `reconcileHistory` keeps the unconfirmed echo forever.

### B7 — Refresh during streaming loops
Every accepted chat event bumps `transcriptRevision`. A `refreshHistory` in flight while deltas arrive fails `revision == transcriptRevision`, sets `needsRefresh`, and `finishLoadingHistory` immediately spawns another refresh. The result is back-to-back `chat.history` (limit 100) requests for the length of the stream, none of which applies.

### B8 — Duplicate assistant row after reconcile
Streaming rows use `"\(runID):assistant"`. A history assistant message with `metadata.runId` but no `entryId` has `historyIdentity` `"\(runId):assistant:"`, with a trailing colon for the empty `toolCallId`. `reconcileHistory` appends the canonical row and then also preserves the still-streaming `"R:assistant"` row, so the reply renders twice.

### B9 — Concurrent `start()` leaks a subscription
`guard eventTask == nil` runs before `await connection.events()`, so two main-actor callers can both pass it: `ChatView`'s `.task` and `AppModel.resync`/`selectSession`. The first task is overwritten and leaks. It keeps calling `receive` after `stopListening()`. `ApprovalStore` already guards this case with `isStarting`.

## Suggested triage

Write each regression test first and confirm it fails on the current code; then fix.

- **B1 plan:** In the `.final` case, if `final.yielded == true`, update the visible row from `final.message` (if present) and keep the run open. Don't call `settle` as terminal, don't set `isTerminal`, and keep `isStreaming`/`activeRunID`. Don't trigger the terminal refresh.
  **B1 tests:**
  - Feed `receive` delta(seq 1) → final(yielded, seq 2) → replacement delta "Replacement" (seq 3) → final (seq 4). Expect the last assistant text to be "Replacement", `!isStreaming` only after seq 4, and exactly one assistant row.
  - Also: after yielded final, `isStreaming == true`.
- **B2 plan:**
  - Add a delivery state to `ConversationMessage` (for example `deliveryFailed: Bool`, default false, keeping `Hashable`). On a `chat.send` failure, mark the optimistic row failed and keep its outbox entry.
  - `retry(idempotencyKey:)` clears the flag and resubmits with the same key. Add a public `retryFailedSends()` that resubmits every failed outbox entry in order. Because the key is idempotent, a duplicate delivery is safe.
  - Have `start()`/`refreshHistory()` callers remain unchanged. Call `retryFailedSends()` from `refreshHistory()` after a successful snapshot, only for entries still unconfirmed by history, so reconnect resync delivers them.
  - Keep `send`'s `true` return meaning "accepted into the transcript", so the composer still clears. Document that in a doc comment.
  - In the message row view, show a compact "Not sent · Retry" control for failed user rows. It needs an accessibility label and a 44-pt target.
  - Change the disconnect copy only if the behavior no longer matches it.
  **B2 tests:**
  - Configure FakeGateway `rpcErrors["chat.send"]` for the first call. Expect the row's `deliveryFailed == true`, and the outbox to still hold the key.
  - Clear the error and call `retry`. Expect a second `chat.send` with the same `idempotencyKey`, then expect the flag cleared.
  - Reconnect path: after the failure, `refreshHistory()` triggers the resend.
  - Confirmed keys are not resent.
- **B7 plan:**
  - Don't discard a snapshot just because streaming events arrived. Apply the page; `reconcileHistory` already preserves streaming rows and unconfirmed echoes.
  - Use the revision check only to decide whether a *follow-up* refresh is needed, and don't schedule a follow-up while `isStreaming` is true. The terminal-event refresh already covers catch-up.
  - Bound follow-ups to one per call.
  **B7 test:**
  - Script a slow `chat.history` reply (`queuedRPCReplies` plus deltas emitted during the request, or drive `receive` between the request and the reply).
  - Expect at most 2 `chat.history` requests after 10 deltas.
  - Expect the snapshot's messages to appear.
- **B8 plan:** In `reconcileHistory`, treat a canonical assistant message whose `metadata.runId == R`, with no `toolCallId`, as the same row as the streaming `assistantMessageID(for: R)`. Adopt the canonical id onto the live row, and skip it in the "preserve streamed assistant" loop. Don't change `historyIdentity`; cache keys depend on it. While here, confirm the run-keyed `pendingAssistantMessages` doesn't mix two assistant entries of one run. Add a test if a fix is needed; otherwise note that it's fine.
  **B8 test:** Stream a delta for R, then `reconcileHistory([assistant "partial", metadata.runId R, no entryId])`. Expect exactly one assistant row. Further deltas update that row.
- **B9 plan:** Add an `isStarting` guard (mirror `ApprovalStore`), or claim `eventTask` synchronously before the await.
  **B9 test:**
  - `async let a = store.start(); async let b = store.start()`, then `stopListening()`.
  - Emit a delta via FakeGateway.
  - Expect `messages` to be empty after a short wait.

Verify by running `ChatCoreTests` and `SystemIntegrationTests` through the simulator test plan (iPhone 18 Pro / iOS 27.0), then build the app.

## Actual fix

