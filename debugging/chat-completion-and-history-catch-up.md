# Chat completion and history catch-up

Date: 2026-10-05. Status: implemented and package-verified; keyboard gesture and physical-phone confirmation pending.

## Summary

The owner reports that the first reply in a new chat leaves the composer showing Stop, subsequent history refresh displays “Couldn’t refresh the conversation. The data couldn’t be read because it is missing,” and downward transcript dragging leaves the keyboard open.

Observed in the installed OpenClaw 2026.9.6 source:

- `chat-history-handler-DMbZf19m.mjs`, `projectChatHistoryDelta`, returns `messages` as session-message envelopes. `session-transcript-message-V86I3uid.mjs`, `projectSessionMessagePayload`, puts the transcript message under `message`. Full history pages instead contain bare messages.
- FancyClaw's cursor decoder expects bare `ChatMessage` entries. A sanitized envelope reproduces `DecodingError.keyNotFound` for `role` at `messages[0]`. A FakeGateway first-send/final/catch-up regression reproduces the owner's exact error banner and leaves the cursor unchanged.
- `session-active-runs-Bm4FXpFw.mjs`, `resolveVisibleActiveSessionRunState`, includes terminal persistence in `hasActiveRun` and can omit `activeRunIds` during that persistence. FancyClaw blindly copies this flag back to `isStreaming` after settling a final. Regressions demonstrate resurrection with absent IDs, a completed ID, and an empty ID list. A mixed snapshot also retains a terminal ID and can prevent the next run's final from clearing the composer.
- `ChatView` sets no scroll keyboard-dismissal behavior.

These are demonstrated client defects consistent with the reports. This turn's retained Xcode console session was expired and contained only a cancellation log, so it cannot establish the physical-phone event sequence. Tests use ephemeral FakeGateway connections; no real Gateway requests were made.

## Suggested triage

1. Verify both enveloped and legacy bare cursor messages, preserving inner transcript identity and rejecting malformed inner messages.
2. Verify that completed run IDs cannot reenter activity snapshots, ambiguous activity booleans preserve live-event state, and a different concrete run can still be recovered. Preserve yielded finals, send acknowledgment races, pagination/reset, and reconnect behavior.
3. Run the seven package targets through the simulator plan, with UI tests excluded. Build the app and extension. Manually check interactive keyboard dismissal in a demo conversation, then confirm first-send/reply/catch-up on the owner's physical phone and Gateway.

## Actual fix

Cursor decoding now unwraps session-message envelopes while retaining support for bare messages. It preserves the inner message's stable ID and run metadata, and still throws on malformed messages. FakeGateway's generated cursor replies now use envelopes, so ordinary catch-up tests exercise the pinned format rather than only a simplified fake response.

History run reconciliation filters known terminal IDs from concrete activity snapshots. An explicit empty ID list clears activity; `inFlightRun.runId` can recover a different run when `activeRunIds` is absent. A boolean-only active flag can recover initial activity but cannot override state already established by chat events. Yielded finals remain active until a real final. No polling or completion timeout was added.

The transcript ScrollView now uses `.scrollDismissesKeyboard(.interactively)` for downward keyboard dismissal.

Verification through the official Xcode MCP on iPhone 18 Pro / iOS 27.0:

- Before correction, the focused reproduction executed 7 cases: 6 failed on the demonstrated defects; the malformed-envelope rejection case passed. Result: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/RunSomeTests/Test-FancyClaw-2026.10.05_14-47-29--0600.xcresult`.
- Final app/extension test build succeeded with zero errors. Log: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261005-145040.txt`.
- Final package run: **321 passed, 0 failed, 0 skipped, 0 not run** across all seven package targets, including envelope decoding, first-reply catch-up, terminal snapshots, alternate run recovery, and yielded run preservation. Explicit `RunSomeTests` selection excluded `FancyClawUITests`; the UI target remains absent from the default test-plan file. Result: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/RunSomeTests/Test-FancyClaw-2026.10.05_14-50-58--0600.xcresult`.
- `git diff --check` passed. No real Gateway traffic or physical-device launch occurred.

The attempted manual simulator gesture check could not proceed: `DeviceInteractionStartWorkspaceSession` requires loading a `device-interaction` skill and delegating interactions to an agent, but that skill is not provided in this environment and was not found in the local skill directories. No interaction events or UI tests were run. The end-session call reported that the session no longer existed. Keyboard gesture behavior and first-send/reply behavior on the owner's physical phone remain unverified.
