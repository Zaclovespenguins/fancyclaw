# Future features

Work deliberately left out of the layout redesign (`layout_redesign.md`). Each entry says why it was deferred and what it would take. The tracked design reference is `Design/openclaw-1b/` (Direction 1b), copied in Slice R1.

## Skills: install and enable/disable (the "+" button and tile toggles)

**Status:** Skills ships read-only in Slice R6. The "+" toolbar button is hidden, and tiles show state without toggles.

**Why deferred:** The pinned Gateway (OpenClaw 2026.9.6) requires `operator.admin` for skill changes. FancyClaw requests only `operator.read`, `operator.write`, and `operator.approvals`.

**What it takes:**
1. **Request admin scope.** Add `.admin` to the scope list in `GatewayConnection` (currently `[.read, .write, .approvals]`). The scope list is signed into the device proof, so the identity and signing tests change too. A paired device will probably need re-approval on the Gateway for the wider scope; check that against a throwaway Gateway. Consider making admin access an explicit opt-in in Settings rather than the default, because it widens what a leaked device identity could do.
2. **Gate the UI on granted scopes.** Follow the `ApprovalStore.hasApprovalScope` pattern: read `hello.auth.scopes` or `connection.grantedScopes`. Show the "+" button and toggles only when admin is granted, and surface missing-scope errors (`MissingScopeErrorDetails`) clearly.
3. **Model the RPCs.** Model the protocol requests and results, and add them to `DEFINITIONS` in `Scripts/refresh-protocol-schema.mjs`:
   - `skills.update`: enable or disable a skill (admin).
   - `skills.install`, plus `skills.upload.begin/chunk/commit` for local bundles (admin).
   - `skills.search` and `skills.detail`: discovery for the "+" sheet.
   - `skills.securityVerdicts`: show the ClawHub verdict before installing.
4. **UI.** The "+" button opens a sheet that searches, shows detail and security verdict, and installs. The skill detail screen (not designed yet) gets the enable toggle, tool list (`tools.catalog` / `tools.effective`), and permissions.
5. **Tests.** Add FakeGateway handlers for each new method, store tests for scope gating, optimistic toggles and failure rollback, and a UI test for the add flow.

## Activity: live timeline with a local cache

**Status:** Slice R7 ships the Activity placeholder with Today and Scheduled segments and empty states. It has no timeline or scheduled-job data; the preview-only `TimelineRow` is not wired to a store.

**Design:** See handoff `README.md` §4 "Activity", `SwiftUI/ActivityView.swift`, and the "Activity · timeline" artboard in `OpenClaw iOS.dc.html` (section 1b).

**Why deferred:** The Gateway has no activity-log RPC. "Today" must be assembled on the client, and "Scheduled" needs cron RPCs that FancyClaw doesn't model yet.

**High-level plan:**
1. **Event model.** Add `ActivityEvent` (id, timestamp, kind `needsYou/running/done`, title, detail, optional sessionKey/runId) and an `@MainActor @Observable ActivityStore` in ChatCore.
2. **Live sources while connected:**
   - `exec.approval.requested/resolved` → needs you / done
   - `agent` lifecycle start/end → running / done
   - `chat` final/error/aborted → done/failed
   - `sessions.changed` → titles and status

   Feed the store from `AppModel`, the same way `ApprovalStore` and `RunActivityStore` are fed today.
3. **Local cache.** Add a `CachedActivityEvent` SwiftData model in `Persistence`, keyed by Gateway URL like `TranscriptCache`, with bounded retention (for example 7 days or N events). Store titles, session references, and statuses only. Like Live Activity state, never store command text, transcript text, or credentials. Debug modes use the in-memory container.
4. **Reconcile on reconnect.** Events missed while disconnected can't be recovered (no replay RPC). After reconnect, compare `sessions.list` status and `lastActivityAt` against the cache, add synthesized "completed while away" entries where a run disappeared, and visibly mark the gap.
5. **Scheduled.** Model `cron.list`, `cron.status`, and `cron.runs`, all `operator.read`. Show upcoming jobs and recent runs. Note that `sessions.list` currently passes `excludeCron: true`, so cron sessions don't appear elsewhere in the app.
6. **Pull to refresh** re-runs the reconnect reconciliation and the cron fetch.
7. **Tests.** Reducer tests for each event source, cache retention and isolation by Gateway, reconciliation after a simulated gap, FakeGateway cron handlers, and a UI test for both segments.

## Chat: step progress and code diff cards

**Status:** Omitted from the Chat restyle (Slice R2).

**Step progress card** ("WORKING · 3 OF 5", done/active/pending rows):
- The likely source is the Gateway `agent` event `plan` stream, which `GatewayProtocol` currently decodes as `.unknown` (see the event notes in `PLAN.md`).
- First capture real `plan` payloads from a throwaway Gateway, then add them to the schema subset and model them in `AgentEvent`.
- `ConversationStore` tracks the latest plan per run and attaches it to the streaming assistant row. The card shows state icons and an elapsed timer.
- Fallback when no plan stream exists: derive steps from the run's tool calls (each `ConversationTool` is a step; running = active).

**Code diff card** (file header with +/− counts and colored lines):
- Source 1: fenced code blocks tagged `diff`/`patch` in agent Markdown. Extend `DesignSystem`'s code-block style to render those with diff chrome instead of plain code.
- Source 2: edit-style tool calls (for example `apply_patch`, or edit tools with old/new text in `arguments`). Compute a unified diff on the client and render it under the tool chip.
- Keep it inside DesignSystem (the only module allowed to depend on Textual), and test parsing separately from rendering.

## Voice mode

**Status:** The composer's voice button is replaced by send-only behavior.

**Options:**
1. **On-device dictation (recommended first step).** Use the Speech framework (`SpeechAnalyzer`/`SpeechTranscriber`, or `SFSpeechRecognizer`) to transcribe into the composer text field. No Gateway changes. It needs `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` in the `Config/` Info.plist fragments, a recording UI state on the button (waveform ↔ stop), and handling for denied permissions.
2. **Gateway talk mode.** The pinned Gateway exposes `talk.session.create`, `talk.client.create/steer/close/transcript/toolCall`, `talk.mode`, and `talk.voice.get/set`. These need the `operator.talk` scope (and maybe `operator.talk.secrets`), which FancyClaw doesn't request. It means real-time audio streaming over the socket. Capture payloads from a throwaway Gateway before designing it.

## Push notifications for approvals (Approve/Deny actions)

**Status:** Not implemented. Approvals arrive only while the socket is connected.

**Blockers and requirements:**
- The current Personal Team signing can't use the Push Notifications capability. This needs a paid Apple Developer Program membership and an APNs key.
- It needs a Gateway-side APNs sender and an RPC to register the device token. Check whether OpenClaw 2026.9.x offers operator push or a webhook/plugin hook. If not, a small relay is needed.
- Add a notification category with **Approve** and **Deny** actions. Mark actions `.authenticationRequired` so approvals can't be made from a locked phone. Each action must connect, complete the handshake, and send `exec.approval.resolve` within the notification-action time budget. This needs the device identity readable after first unlock.
- Approvals are transient and expire, so a notification for an expired or already-handled request must say so rather than fail silently.
- Possible interim step: local notifications for approvals that arrive while the app is backgrounded but the socket is still alive. This is limited, because the socket doesn't survive long in the background.

## Smaller deferred items

- **Chat "Share" action.** The design's ••• menu has Share, but there's no backend for it. It could export the loaded transcript as Markdown text through `ShareLink`. Omitted in R2.
- **Theme picker.** R1 adds the theme infrastructure and a placeholder row in Settings, with only the default (coral) theme. Adding themes means defining new `AppTheme` token sets (light and dark variants each) and enabling the picker.
- **Running card progress.** Home's Running cards show a spinner only. A timer (from the run's `startedAt`) or real progress would need a Gateway progress signal, which the pinned release doesn't send.
- **Full Skill detail screen.** R6 ships a minimal read-only detail sheet from Skills tiles. A full detail screen is not designed; additions such as an install flow, tools list, and permissions remain deferred.

## Accessibility audit follow-up

**Status:** Deferred at the owner's request on 2026-10-03. Automated accessibility-only audit checks were removed; functional navigation, chat, approval, Settings and screenshot coverage remains.

**Observed findings:** Native Chats search clipping; rich-output text measured outside the transcript viewport; partial Dynamic Type support reported on file metadata and multiline SwiftUI text. Earlier runs also flagged nested attachment-caption grouping despite readable screenshot text. These findings are not claimed fixed. Custom caption aggregation was removed so the native text children remain exposed.

**Later work:** Reproduce on supported iOS runtimes, inspect VoiceOver and actual text scaling, distinguish layout defects from audit artifacts, and restore focused audit coverage when addressing accessibility. The completed pre-deferral report and diagnostics are recorded in `.claude/deviations/redesign-r3-link-previews.md`.
