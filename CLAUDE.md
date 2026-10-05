# FancyClaw

A SwiftUI iOS operator client for a single OpenClaw Gateway. `PLAN.md` holds the architecture, pinned protocol reference, and vertical slices. Read it before starting a slice.

`AGENTS.md` is a tracked symlink to this file (`CLAUDE.md`). Edit this file to keep both entry points in sync; preserve the symlink.

`.claude/plan-deviations.md` logs implementation departures, settled questions, and verification results. Read it alongside the plan; later entries supersede earlier decisions. When a slice departs from the plan, add an entry. For the layout redesign (`layout_redesign.md`), write each deviation to its own file under `.claude/deviations/` and add only a one-line pointer to the log's "Layout redesign" section; deferred work goes in `Future_features.md`. Some introductory/scaffold descriptions in `PLAN.md` are historical; check the implementation and deviations before treating them as current status.

`debugging/` holds investigation notes with concise, descriptive filenames and titles (for example, `session-event-decoding.md`, titled “Session event decoding failure”). Each note starts with its title, date, and status, then has **Summary** (symptoms, evidence, and cause; distinguish observations from inference), **Suggested triage** (next diagnostic and verification steps), and **Actual fix**. Leave **Actual fix** blank until the agent that fixes the issue fills it in with a short description of the implemented correction and verification results. Keep proposed fixes in **Suggested triage** and update the note's status once verified. Read relevant notes before investigating a matching issue.

## Current status (2026-10-05)

- Original implementation slices 0–11 are complete. The dashboard redesign R1–R7 is implemented: Home, Chats, Skills, Activity, a detached compose action, per-tab navigation, restyled chat and Settings. Skills is read-only; Activity is an empty Today/Scheduled placeholder with no Gateway data.
- Latest successful full-plan verification was the completed redesign (2026-10-04) on iPhone 18 Pro / iOS 27.0: **349 passed, 0 failures, 0 skips** (310 Swift Testing + 39 UI tests). The app/extension build has zero errors, and all 32 Home/Chats/Skills/Activity light/dark default/XXL screenshots were reviewed. Evidence is recorded in `.claude/deviations/redesign-r7-activity.md`.
- UI tests are disabled in the default shared test plan at the owner's request (2026-10-05). Run all seven package test targets by default; preserve UI tests and re-enable them only when the owner asks. Worktree integration and current verification are recorded in `.claude/deviations/worktree-integration.md`.
- Accessibility-only audit and repair are deferred at the owner's request. Functional UI assertions and light/dark default/XXL screenshot coverage are preserved in the disabled UI-test target; see `.claude/deviations/redesign-accessibility-deferred.md`.
- Personal Team/personal use; no ordinary widgets, launcher widget, App Group, or TestFlight scope. The extension hosts only the New Chat Control and Live Activity. SwiftData is app-private.
- Physical haptic feedback, device provisioning, camera/Bonjour behavior, real Gateway uploads/pairing/reconnect, local-authentication prompts, spoken Siri/Spotlight, and Control Center gallery placement still need device/live checks. Only iOS 27.0 is installed here; the iOS 26 deployment floor remains unverified.

## Layout

- `FancyClaw.xcodeproj`: app (`FancyClaw/`), WidgetKit extension (`FancyClawWidgets/`), UI tests (`FancyClawUITests/`). It uses folder-synchronized groups, so new files in those folders join their target automatically. Don't edit `project.pbxproj` per file or re-run scaffolding. Open this project directly, not a separate workspace.
- `FancyClaw/AppModel.swift`: app routing, connection lifecycle, per-session conversation stores, cache, approvals, skills, and intent/activity coordination. App UI is grouped under `FancyClaw/Home/`, `Sessions/`, `Skills/`, `Activity/`, `Chat/`, and `Settings/`; `FancyClaw/Root/RootView.swift` hosts the tab shell. `FancyClaw/SystemIntegration/` owns shortcut phrases and the concrete ActivityKit driver.
- `Packages/FancyClawKit`: iOS-only local package (Swift tools 6.2, Swift 6 language mode) holding testable logic; module responsibilities are listed below.
- `Config/`: `Shared.xcconfig` (team, bundle-ID prefix, versions, deployment target), Info.plist fragments merged into generated plists, and empty entitlement files. This synchronized group belongs to no target; don't add it to resource membership.
- `FancyClaw.xctestplan`: the shared scheme's test plan. It runs all **seven package test targets** by default; `FancyClawUITests` is excluded from this plan until the owner asks to re-enable UI testing; its project target and source remain intact. There is no app-level `FancyClawTests` target. `SystemActions` is covered by `SystemIntegrationTests`. **When you add a package test target, add it here too.**
- `Scripts/refresh-protocol-schema.mjs`: refreshes the schema subset in `TestSupport/Fixtures` from the pinned npm release. Keep its release constant synchronized with `ProtocolVersion.pinnedRelease`; extend `DEFINITIONS` when adding modeled schema shapes.

| Module | Responsibility |
| --- | --- |
| `GatewayProtocol` | Pure Codable frames/models, tolerant decoding, strict outbound encoding; protocol 4, OpenClaw 2026.9.6, including read-only Skills status. |
| `GatewayClient` | Socket actor, identity/Keychain, handshake, pairing/discovery, transport/media policy, lifecycle and injected timing. |
| `ChatCore` | Conversation/session/approval/skills stores, history, streaming/throttle, attachment preparation, idempotent outbox, and skill presentation. |
| `Persistence` | `CachedSession`, `CachedMessage`, `CachedHistory`, and private SwiftData `TranscriptCache`. |
| `DesignSystem` | Theme tokens, ambient glow, glass/surface helpers, Markdown styling, code-block chrome, image-loader adapter, spacing; only module directly depending on Textual. |
| `TestSupport` | Ephemeral loopback `FakeGateway`, schema/frame fixtures, deterministic demo helpers. |
| `SystemActions` | Shared New Chat action/intent, destination, ActivityKit attributes and session URLs; no cache/Gateway dependency. |
| `SystemIntegration` | App-only Ask/Open intents, cached session entities/query, activity reducer/store and driver interface. |

## Conventions

- iOS 26+, iPhone only, portrait only, Swift 6 language mode with strict concurrency.
- App and widget targets default to `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Package modules don't, so mark isolation explicitly: `actor` for the socket, `@MainActor @Observable` for stores.
- Observation, not Combine. Own application state through injected instances; reuse the app's `ModelContainer`. System intents register injected services with Apple's `AppDependencyManager.shared`. `os.Logger` for logging. Inject timing through `GatewayTiming`/`Clock` so sleeps and deadlines are testable.
- Swift Testing (`@Test`, `#expect`) for unit tests. XCTest only for UI tests.
- Tests never touch the real Gateway on `127.0.0.1:18789`. Use `FakeGateway` from `TestSupport`, or a throwaway Gateway for `.live` tests (ask first).
- Protocol models decode tolerantly (unknown enum values become `.unknown`) but encode strictly: the Gateway's schemas are closed, so never send extra keys.
- Only add third-party dependencies with the owner's approval. Textual is the only direct external dependency, constrained to 0.5.x; its transitive dependencies are in `Package.resolved`. Use Textual for Markdown parsing.

## Implementation boundaries

- The Gateway is the source of truth. Cache canonical history/session metadata by Gateway URL; credentials and device identity stay in Keychain. Persist media references, not attachment bytes, base64, or inline data URLs. Debug Gateway modes use ephemeral identities and in-memory caches.
- SwiftData uses `groupContainer: .none`; neither target has App Group entitlements. The extension links only `SystemActions`, with no database, credentials, or socket access.
- All three system actions open the main app and require local device authentication. Reuse its connection; Ask waits up to 25 seconds after acknowledgment, then lets the run continue in the app. Intent metadata is extracted directly; `AppIntentsPackage` wrappers broke discovery on this toolchain (see Slice 10 deviations).
- Live Activities update locally, with no push/background WebSocket guarantee. Background/disconnect shows uncertainty; foreground catch-up reconciles runs. Activity state excludes transcript text, tool commands, and credentials.
- Exec approvals are connection-wide and transient, with no recovery RPC for requests missed while disconnected. Session deletion archives first, then sends `archivedOnly: true`, as required for `operator.write` in the pinned Gateway release.

## Build, test & debug (official Xcode MCP server)

Use Apple's official Xcode MCP server for builds, tests, device interaction, debugger commands, and console logs.

1. Use `XcodeListWorkspaces` to find this checkout's open project and pass its `workspaceIdentifier` to subsequent calls. If access needs approval or the project is not open, use `XcodeOpenWorkspace` with the absolute path to `FancyClaw.xcodeproj`. For logs from an app already running in the Xcode UI, select its window-tab workspace rather than a separate background workspace.
2. Confirm scheme `FancyClaw`, Debug configuration, and simulator `iPhone 18 Pro` (iOS 27.0) for automated checks. Use `XcodeListSchemes` / `XcodeListRunDestinations` and their switch tools as needed. Use a physical iPhone when the task calls for device verification.
3. `BuildProject` builds the app and embedded extension. `RunAllTests` runs the active scheme's enabled test targets; confirm `FancyClaw` is the active test plan. The default suite contains the seven package targets, with UI testing disabled until the owner asks to re-enable it. Inspect reported counts and returned logs, including Swift Testing totals.
4. Use `RunProject` to build and launch; set `attachDebugger: true` when debugging. `GetConsoleOutput` reads stdout, stderr, and OSLog from the current or specified launch session. Check its session state and reference so retained logs from an expired session are not mistaken for current output. `InvokeDebuggerCommand` sends LLDB commands to an attached debugger.
5. Use the `DeviceInteraction` tools for screenshots and UI hierarchy checks; end interaction sessions when finished. Automated UI testing is currently disabled at the owner's request; do not add it back to default verification or launch UI tests unless asked. Manual UI checks may still be used when relevant.

The package imports iOS frameworks; host `swift test` is not the full-suite workflow. Run package tests through the simulator test plan.

Debug launch modes are implemented in `AppModel.prepareOnce()`: `-OnboardingPreview` bypasses saved profiles; `-FakeGateway` shows onboarding with an ephemeral manual endpoint. FakeGateway demos cover Conversation, Attachments, Approvals, System Integration, Offline/Approval Focus/Session Action Error, Link Previews, Home (including send/model errors), Sessions (including empty), and Skills (including empty/error/offline). `LaunchArgument` lists only a subset. `-PolishLight` and `-PolishDark` force appearance for checks, combined with a debug mode and optional `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXL`.

Disk space fluctuates; check `df -h .` before expensive build/test cycles rather than relying on old estimates. If a build hits "No space left on device", stop and tell the owner. Don't delete DerivedData, caches, or simulators.

## Git

Inspect `git status` before work. Commit after each slice, staging only your changes; preserve unrelated edits and worktrees. Never commit `.claude/settings.local.json`, credentials, or local environment files. Don't push or add a remote.
