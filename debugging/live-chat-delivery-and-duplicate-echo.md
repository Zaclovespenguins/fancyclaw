# Live chat reply delivery and duplicate user echo

Date: 2026-10-02. Status: fixed and verified against the live Gateway from iOS Simulator; physical-phone lock/unlock pending.

## Summary

The owner sent a message in a new chat on the phone. The user bubble appeared, but the UI stayed on “Thinking…” without a reply. After locking and unlocking the phone, the reply appeared, followed by another copy of the original user message. Foreground reconnect/history catch-up is a plausible explanation for the reply appearing, but that transition was not instrumented during the phone reproduction.

### Console observations

Inspected all 2,190 entries returned for Xcode's running FancyClaw launch session `72e72f600`, PID 10168. No Gateway decoding, receive-loop termination, or recovery errors were logged. This does not prove successful live event delivery: successful sends/events are not comprehensively logged. The previous missing-`reason` decoding failure in `session-event-decoding.md` was not observed here.

The console separately reported duplicate model-picker IDs `gpt-5.6-luna` and `gpt-6-luna` at approximately 12:24:35 America/Denver. `AgentModelPicker` uses `ForEach(store.models)` and `ModelSummary.id` excludes the provider, while `selectionID` includes it. This is a separate observed identity problem; no causal link to the missing reply was established. Keyboard, layout, and system-service warnings also appeared without a demonstrated connection to this issue.

### Live reproduction

The owner explicitly authorized checks against the real Gateway and supplied `.env.live`. Git ignores this file via `.env.*`. It specifies `ws://localhost:18789/` and a token; do not copy credentials into tracked files, fixtures, or logs. Live permission in this session superseded the normal instruction to avoid the owner's instance. Future agents should obtain authorization for additional live writes if not already covered by their session.

Executed a temporary official Xcode `RunCodeSnippet` in the context of `FancyClaw/AppModel.swift`, using the actual `GatewayConnection` and `ConversationStore`. This was a diagnostic check, not a run of the automated test suite. No app or test sources were changed. The exact runtime device/OS was not recorded by the snippet result; do not describe this as a verified physical-phone automation run.

Procedure:

1. Read the ignored config directly at runtime without printing its values. Generate an ephemeral device identity and connect without a persistent identity store.
2. Call `sessions.create` with default parameters, creating only this new diagnostic conversation: `agent:main:dashboard:8b255a32-e5d6-4db6-abee-57e8beba7ee1`.
3. Subscribe to the connection's local `events()` stream in a diagnostic task. Print any decoded `chat` event's session-key equality and sequence, or an `AGENT event` marker.
4. Construct `ConversationStore(connection: connection, sessionKey: created.key, streamingInterval: .zero)` and call `start()` before sending.
5. Send a unique message of the form `FancyClaw diagnostic <UUID>. Reply only OK. Do not use tools.` through the store. Wait 45 seconds.
6. Fetch typed `chat.history` with the created key and limit 100. Inspect role counts and the presence (not values) of the canonical user's idempotency key and entry ID.
7. Call `store.refreshHistory()` and count user rows whose text exactly equals the unique diagnostic message. Cancel the diagnostic event consumer, stop the store listener, and disconnect. The diagnostic conversation was left on the Gateway; it was not archived or deleted.

Returned output:

```text
PASS handshake
PASS create key=agent:main:dashboard:8b255a32-e5d6-4db6-abee-57e8beba7ee1
SEND errorPresent=false thinking=true
LIVE assistantRows=0 thinking=true
HISTORY keyMatches=true userRows=1 assistantRows=1
USER idempotencyKeyPresent=true entryIDPresent=true
RECONCILE matchingUserRows=2 assistantRows=1 thinking=false
```

No `CHAT` or `AGENT event` lines appeared. The observer did not print other event types or raw frames, so this is evidence of no decoded chat/agent events observed by that subscription, not proof that the socket received no frames. Unlike the phone, this reproduction obtained the reply through history refresh on the same connection without reconnecting.

Authentication, session creation, send without a surfaced error, and history retrieval succeeded. Live reply delivery and unique user-message reconciliation failed. Gateway history already contained an assistant reply after 45 seconds while the store had none. The canonical user had an idempotency key and stable entry ID, so absence of those fields is not the demonstrated duplication cause. Their equality to the submitted key was not checked. The acknowledgment status/run ID and installed Gateway version were not recorded.

### Relevant implementation and limits

- `GatewayConnection.connect` advertises `.sessionScopedEvents` in its client capabilities. Investigate the pinned/installed protocol's server-side subscription requirements. A local `events()` consumer is not necessarily a server subscription. The diagnostic did not invoke `sessions.subscribe`; production `SessionStore.refresh()` does, so reproduce with production-equivalent subscriptions before concluding the precise cause.
- `ConversationStore.start()` installs a local event consumer. `receive` accepts only decoded `.chat` events with an exact session-key match and nonempty run ID, then rejects terminal runs or non-increasing sequences. The diagnostic observer precedes these store filters, and observed no chat events, making a store-only key filter insufficient to explain that diagnostic result.
- `submit` sets `isStreaming = true` before awaiting `chat.send`, adopts the acknowledged run ID, and ordinarily relies on terminal events/history to clear the state. A visible optimistic bubble alone does not prove delivery. There is no bounded post-acknowledgment recovery in this path when the expected stream never arrives.
- `reconcileHistory` confirms outbox entries only using canonical `message.idempotencyKey`. Unconfirmed optimistic user rows are appended after canonical history, which matches the duplicate appearing after the assistant reply. Compare the actual submitted key, server run ID, canonical key and stable entry ID before choosing a matching rule.
- Existing FakeGateway tests do not establish compatibility with real event routing or real history identities. Read `chat-core-fixes.md` and `app-integration-fixes.md` for recent concurrency, yielded-final, stale-snapshot, and foreground fixes; preserve their guarantees.

## Suggested triage

1. Inspect installed Gateway source/protocol for routing when `sessionScopedEvents` is advertised, including any chat-session subscription RPC and how `sessions.subscribe` differs. Use local source or authoritative documentation; record the installed version. Capture sanitized event names, session/run identity comparisons and sequence numbers, never tokens or real transcript contents.
2. Reproduce the exact production new-chat flow, including roster/server subscriptions and an initial history refresh. Compare with a subscribed existing chat. Determine whether the server emits chat events to this socket at all, whether a subscription is missing, or whether frames are dropped before the typed observer.
3. Capture acknowledgment status/run ID and compare canonical user identity to the sent idempotency key. Prefer equality diagnostics or sanitized fixtures over logging actual user data. Do not fix this by deduplicating arbitrary identical text: repeated user messages are legitimate.
4. Add focused failing regressions using sanitized real event/history shapes and FakeGateway behavior that enforces the relevant subscription contract. Verify one optimistic echo becomes one canonical user row, live deltas/final arrive without reconnect, and terminal events cannot be missed by new-chat setup. Keep idempotent retry, yielded-final and stale-history protections intact.
5. Consider bounded history reconciliation for an acknowledged run with missing events as a recovery mechanism after resolving the routing cause. Avoid an unconditional short timeout that aborts legitimate long-running model/tool work.
6. Verify a fresh new chat and phone lock/unlock behavior against the authorized live instance, recording runtime and Gateway version. Use a new dedicated diagnostic session, avoid existing chats, and do not run destructive session/approval tests against the owner's data. Run appropriate simulator package/UI regressions through the official Xcode test plan; the whole current suite cannot simply be redirected to a live endpoint.

### Implementation plan (2026-10-02)

1. Register `sessions.messages.subscribe` before a conversation listens, sends, or loads history. Keep registration in the socket actor, scoped to its connection generation, and clear it on disconnect. Roster subscription alone is insufficient. Retain registrations for conversation stores and Live Activities until the connection closes.
2. Confirm optimistic user sends against either the exact submitted key (legacy/FakeGateway shape) or the pinned Gateway's exact `<submitted-key>:user` identity. Only user entries confirm sends; never compare transcript text.
3. Make FakeGateway optionally enforce per-socket message subscriptions and use the pinned canonical user key shape. Add failing delivery/reconnect and duplicate-echo regressions; preserve prior race/yield/retry protections.
4. Build and run the simulator test plan. Repeat production-equivalent new-chat send/history/reconnect checks against the authorized live endpoint, using dedicated diagnostic conversations and sanitized output. Record physical lock/unlock separately if it cannot be automated.

Evidence: installed package and live hello both report 2026.9.6. `server-start-BG4nMCFD.mjs` gates session subscription events on `sessionMessageSubscribers` for `SESSION_SCOPED_EVENTS`; `sessions-subscriptions-DE125CeG.mjs` separates roster and message registration. A live snippet with both subscriptions observed chat sequences 1, 2, 4, 6, 10; acknowledgment `started`, run ID equal to submitted key; canonical user key unequal to submitted key and equal to `<submitted-key>:user`.

## Actual fix


Implemented 2026-10-02:

- `GatewayConnection.subscribeToSessionMessages` registers the key with `sessions.messages.subscribe`, checks `subscribed: true`, and remembers successful registrations only for the current socket generation. Disconnect clears them; a stale acknowledgment cannot register a new socket. Subscriptions remain for the socket lifetime, covering conversations retained by the app and their Live Activities.
- `ConversationStore.start` installs the local consumer before server registration and re-registers when an existing consumer survives reconnect. History refresh and submit also ensure registration, including Ask without a ChatView listener. A failed registration surfaces an error and prevents a send with missing event routing.
- History confirms outbox entries only from user messages whose identity equals the submitted key or exactly `<submitted-key>:user`. Canonical entry IDs are preserved. Matching text, unrelated keys and assistant identities cannot remove optimistic rows. The confirmed outbox entry is removed, so it cannot be retried again.
- FakeGateway now supports opt-in per-socket message subscription enforcement and writes the pinned user-key suffix. `LiveDeliveryTests` adds four regressions for first-send/reconnect delivery, suffixed user identity with repeated text, assistant identity exclusion and denied subscriptions. The delivery and suffix regressions failed on the old code; all four pass after the fix.
- No polling timeout was added: the demonstrated cause was server routing, and the corrected stream delivers terminal events. Existing yielded-final, stale-snapshot, idempotent retry and foreground behavior remain covered by the package suite. The separate model-picker identity warning is outside this correction.

Verification:

- Official Xcode `BuildProject(buildForTesting: true)` succeeded for FancyClaw and its extension on iPhone 18 Pro / iOS 27.0. Final build log: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/E1363761-2DB4-4D3D-8616-E2F56C4FA97E/BuildProject/BuildProject-Log-20261002-130415.txt`.
- Full FancyClaw plan executed **363 cases including parameterized cases: 360 passed, 3 failed, 0 skipped**. All **350 package cases passed**, plus 10 of 13 UI tests. Failures: `PolishTests.testChatAndDrawerAccessibility` (contrast/potentially inaccessible text), `testLargeTextDarkMode` (contrast/potentially inaccessible text) and `testRichOutputAccessibilityAndLargeText` (contrast). Two were previously documented; the extra dark audit failure's baseline has not been isolated. These UI failures remain unresolved and the full suite is not green.
- `RunAllTests` returned an incomplete-bundle error, but the finalized current result was recovered using `xcresulttool get object --legacy` from a temporary copy. Both root metrics and per-target results were inspected; all four new tests succeeded. Original bundle: `/Volumes/SSDCache/Xcode/DerivedData/FancyClaw-cuslxoojkxbnodaxyjxcjqyjwuhl/Logs/Test/Test-FancyClaw-2026.10.02_12-52-16--0600.xcresult`. Temporary copy: `/private/tmp/fancyclaw-live-delivery-full.xcresult`.
- After removing an unused-result warning in FakeGateway, final focused `RunSomeTests`: **4 passed, 0 failed**. Summary: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/E1363761-2DB4-4D3D-8616-E2F56C4FA97E/RunSomeTests/5217D786-1902-4092-8BC3-35C479E67B15.txt`.
- Authorized live verification used the real connection and ConversationStore through official `RunCodeSnippet`, with no manual message-subscription RPC. Runtime explicitly reported **iOS Simulator 27.0 (24A5355p)**, Gateway hello **2026.9.6**. Created one fresh dedicated diagnostic session, subscribed to roster updates, started/refreshed the store, sent a unique diagnostic, then disconnected/reconnected and sent the identical text again. Each turn waited up to 45 seconds for a completed visible assistant reply before history refresh. Output:

```text
LIVE turn=1 assistantRows=1 thinking=false errorPresent=false
RECONCILE turn=1 matchingUserRows=1 expected=1
LIVE turn=2 assistantRows=2 thinking=false errorPresent=false
RECONCILE turn=2 matchingUserRows=2 expected=2
PASS fresh-chat delivery, history echo, repeated text, reconnect delivery
```

The baseline and final checks created two dedicated live diagnostic conversations in total; neither was archived or deleted. Credentials and real transcript text were not printed or persisted. Physical-phone lock/unlock and the iOS 26 floor were not verified.
