# FancyClaw

A SwiftUI iOS operator client for an OpenClaw Gateway. `PLAN.md` holds the architecture, protocol reference, and the vertical slices. Read it before starting a slice.

## Layout
- `FancyClaw.xcodeproj`: app (`FancyClaw/`), widget extension (`FancyClawWidgets/`), UI tests (`FancyClawUITests/`). It uses folder-synchronized groups, so new files in those folders join their target automatically. Don't edit `project.pbxproj` per file.
- `Packages/FancyClawKit`: local package holding all testable logic. Modules: `GatewayProtocol` (pure Codable), `GatewayClient`, `ChatCore`, `Persistence`, `DesignSystem` (the only module that depends on Textual), `TestSupport`. Each has a `<Module>Tests` target.
- `Config/`: `Shared.xcconfig` (team, bundle-ID prefix, versions, deployment target), Info.plist fragments merged into the generated plists, and entitlements.
- `FancyClaw.xctestplan`: the scheme's test plan. It runs every package test target plus the UI tests. **When you add a package test target, add it here too.**

## Conventions
- iOS 26+, iPhone only, Swift 6 language mode with strict concurrency.
- App and widget targets default to `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Package modules don't, so mark isolation explicitly: `actor` for the socket, `@MainActor @Observable` for stores.
- Observation, not Combine. No singletons except the `ModelContainer`. `os.Logger` for logging. Inject `Clock` so timing logic is testable.
- Swift Testing (`@Test`, `#expect`) for unit tests. XCTest only for UI tests.
- Tests never touch the real Gateway on `127.0.0.1:18789`. Use `FakeGateway` from `TestSupport`, or a throwaway Gateway for `.live` tests (ask first).
- Protocol models decode tolerantly (unknown enum values become `.unknown`) but encode strictly: the Gateway's schemas are closed, so never send extra keys.
- Only add third-party dependencies with the owner's approval. Textual is the only one.

## Build & test (XcodeBuildMCP)
1. `session_show_defaults`. If unset, run `session_set_defaults` with this `projectPath`, scheme `FancyClaw`, simulator `iPhone 18 Pro` (iOS 27.0), configuration `Debug`, and bundleId `com.zacisnotacompany.fancyclaw`.
2. `build_sim` builds the app and the embedded widget.
3. `test_sim` runs the whole test plan (takes about 4 min, mostly the UI test). The MCP summary undercounts Swift Testing results, so check the `✔ Test run with …` lines in the build log.
4. `build_run_sim`, then `screenshot` / `snapshot_ui` for visual checks.

Disk space is tight (about 5 GB free). If a build hits "No space left on device", stop and tell the owner. Don't delete DerivedData, caches, or simulators.

## Git
Commit after each slice. Don't push or add a remote.
