# FancyClaw

A SwiftUI iOS operator client for a single OpenClaw Gateway. `PLAN.md` holds the architecture, pinned protocol reference, and vertical slices. Read it before starting a slice.

`AGENTS.md` is a tracked symlink to this file (`CLAUDE.md`). Edit this file to keep both entry points in sync; preserve the symlink.

`.claude/plan-deviations.md` logs implementation departures, settled questions, and verification results. Read it alongside the plan; later entries supersede earlier decisions. When a slice departs from the plan, add an entry. Some introductory/scaffold descriptions in `PLAN.md` are historical; check the implementation and deviations before treating them as current status.

## Current status (2026-09-30)

- Slices 0–11 are implemented: project/protocol, identity/handshake, onboarding, connection recovery, streaming chat, history/session management/private cache, rich output, attachments, exec approvals, system integration, and polish.
- Slice 11 includes optional haptics, error banners, accessibility/Dynamic Type fixes, a layered Icon Composer icon, and `FancyClawUITests/PolishTests.swift`. Choices and verification are recorded in the deviations log.
- Latest full-suite verification is Slice 11 on iPhone 18 Pro / iOS 27.0: **190 passed, 0 failures, 0 skips** (177 Swift Testing + 13 UI tests). Logs and the initial launch measurement are linked in the deviations entry.
- Personal Team/personal use; no ordinary widgets, launcher widget, App Group, or TestFlight scope. The extension hosts only the New Chat Control and Live Activity. SwiftData is app-private.
- Physical haptic feedback, device provisioning, camera/Bonjour behavior, real Gateway uploads/pairing/reconnect, local-authentication prompts, spoken Siri/Spotlight, and Control Center gallery placement still need device/live checks. Only iOS 27.0 is installed here; the iOS 26 deployment floor remains unverified.

## Layout

- `FancyClaw.xcodeproj`: app (`FancyClaw/`), WidgetKit extension (`FancyClawWidgets/`), UI tests (`FancyClawUITests/`). It uses folder-synchronized groups, so new files in those folders join their target automatically. Don't edit `project.pbxproj` per file or re-run scaffolding. Use `projectPath`, not a separate workspace.
- `FancyClaw/AppModel.swift`: app routing, connection lifecycle, per-session conversation stores, cache, approvals, and intent/activity coordination. `FancyClaw/SystemIntegration/` owns shortcut phrases and the concrete ActivityKit driver.
- `Packages/FancyClawKit`: iOS-only local package (Swift tools 6.2, Swift 6 language mode) holding testable logic; module responsibilities are listed below.
- `Config/`: `Shared.xcconfig` (team, bundle-ID prefix, versions, deployment target), Info.plist fragments merged into generated plists, and empty entitlement files. This synchronized group belongs to no target; don't add it to resource membership.
- `FancyClaw.xctestplan`: the shared scheme's test plan. It runs all **seven package test targets** plus `FancyClawUITests`; there is no app-level `FancyClawTests` target. `SystemActions` is covered by `SystemIntegrationTests`. **When you add a package test target, add it here too.**
- `Scripts/refresh-protocol-schema.mjs`: refreshes the schema subset in `TestSupport/Fixtures` from the pinned npm release. Keep its release constant synchronized with `ProtocolVersion.pinnedRelease`; extend `DEFINITIONS` when adding modeled schema shapes.

| Module | Responsibility |
| --- | --- |
| `GatewayProtocol` | Pure Codable frames/models, tolerant decoding, strict outbound encoding; protocol 4, OpenClaw 2026.9.6. |
| `GatewayClient` | Socket actor, identity/Keychain, handshake, pairing/discovery, transport/media policy, lifecycle and injected timing. |
| `ChatCore` | Conversation/session/approval stores, history, streaming/throttle, attachment preparation, idempotent outbox. |
| `Persistence` | `CachedSession`, `CachedMessage`, `CachedHistory`, and private SwiftData `TranscriptCache`. |
| `DesignSystem` | Markdown styling, code-block chrome, image-loader adapter, spacing; only module directly depending on Textual. |
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

## Build & test (XcodeBuildMCP)

1. `session_show_defaults`. If unset or pointing at another checkout, run `session_set_defaults` with this checkout's absolute `projectPath`, scheme `FancyClaw`, simulator `iPhone 18 Pro` (iOS 27.0), configuration `Debug`, and bundleId `com.zacisnotacompany.fancyclaw`. Keep `persist: false`; `.xcodebuildmcp/config.yaml` tracks workflows, not absolute checkout paths or simulator UDIDs.
2. `build_sim` builds the app and the embedded widget.
3. `test_sim` runs the whole test plan; allow several minutes for UI/system tests. The MCP summary can undercount Swift Testing results, so check the `✔ Test run with …` lines and UI totals in the build log.
4. `build_run_sim`, then `screenshot` / `snapshot_ui` for visual checks. UI slices also require light/dark, Dynamic Type, and accessibility checks appropriate to the change.

The package imports iOS frameworks; host `swift test` is not the full-suite workflow. Run package tests through the simulator test plan.

Debug launch modes are implemented in `AppModel.prepareOnce()`: `-OnboardingPreview` bypasses saved profiles; `-FakeGateway` shows onboarding with an ephemeral manual endpoint; `-DemoConversation`, `-DemoAttachments`, `-DemoApprovals`, and `-DemoSystemIntegration` connect and seed the relevant screen. `LaunchArgument` currently lists only a subset. `-PolishLight` and `-PolishDark` force appearance for checks, combined with a debug mode and optional `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXL`.

Disk space fluctuates; check `df -h .` before expensive build/test cycles rather than relying on old estimates. If a build hits "No space left on device", stop and tell the owner. Don't delete DerivedData, caches, or simulators.

## Git

Inspect `git status` before work. Commit after each slice, staging only your changes; preserve unrelated edits and worktrees. Never commit `.claude/settings.local.json`, credentials, or local environment files. Don't push or add a remote.
