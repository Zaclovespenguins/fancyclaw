# Plan deviations log

Where the implementation departs from `PLAN.md`, or settles something the plan left open. Read this alongside the plan before starting a slice. When a slice departs from the plan, add an entry under that slice: say what changed, why, and whether a later slice needs to act on it.

---

## Slice 0: Project skeleton & tooling (2026-09-29, commit `a5a48ea`)

### Departures from the plan
- **Scaffold output not kept.** The plan said to use XcodeBuildMCP `scaffold_ios_project` if it's enabled. It is, but its template is dated: Swift 5, iOS 18.4 deployment target, a workspace plus a `FancyClawPackage/` layout, no widget target, and extra `.cursor`/`.github` rules files. I used its output only as a reference and wrote `FancyClaw.xcodeproj/project.pbxproj` by hand. Object IDs follow a readable `FC00…00NN` scheme. Don't re-run the scaffold on top of this project.
- **No `.xcworkspace`.** It's a plain `FancyClaw.xcodeproj` that references `Packages/FancyClawKit` through `XCLocalSwiftPackageReference`, and the XcodeBuildMCP defaults use `projectPath`, not `workspacePath`.
- **No app-level `FancyClawTests` target.** The Architecture diagram lists `FancyClawTests / FancyClawUITests`, but every unit test lives in the package (`<Module>Tests` for each of the six modules), and `FancyClaw.xctestplan` pulls them in. Only `FancyClawUITests` exists on the app side. Add an app-level unit test target only if app-target code (App Intents in Slice 10, say) needs tests that can't live in the package.
- **App Group not verified.** Both targets declare `group.com.zacisnotacompany.fancyclaw` in `Config/*.entitlements`, and the simulator build succeeds. But simulator builds are ad-hoc signed and don't validate App Groups or the team, so we still don't know whether team `NWV8LZ45D5` is a Personal Team. **Resolve this before Slice 10.**
- **iOS 26 simulator runtime not added.** The plan marks this optional. I skipped it because of disk space, so the deployment-target floor (iOS 26.0) is still unchecked, and everything so far has run on iOS 27.0.

### Choices the plan left open
- **iPhone, portrait only** (`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`). The plan only says "iPhone only", so this is easy to revisit.
- **App and widget targets default to `MainActor` isolation** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, member-import visibility on), matching Xcode 26+ templates. **Package modules don't use default isolation**, so mark it explicitly there (`actor`, `@MainActor`).
- **The package is iOS-only** (`platforms: [.iOS(.v26)]`, tools 6.2, Swift 6 language mode), so there are no fast `swift test` runs on the macOS host and all tests go through `test_sim`. Adding macOS would mean `#if canImport(UIKit)` guards in DesignSystem and similar code.
- **Info.plist:** `GENERATE_INFOPLIST_FILE = YES` for the simple keys, plus partial plists (`Config/FancyClaw-Info.plist` and `Config/FancyClawWidgets-Info.plist`) for the array and dictionary keys (`NSBonjourServices`, `NSAppTransportSecurity`, widget `NSExtension`). ATS combines `NSAllowsLocalNetworking` with an `NSExceptionDomains` entry for `ts.net` (subdomains, insecure loads). Tailscale CGNAT addresses are bare IPs, which ATS doesn't restrict.
- **`Config/` is a synchronized group that belongs to no target.** It's there only so the xcconfig base-configuration anchor and the plist/entitlements paths resolve. Don't add it to a target, or its plists get copied as resources.
- **Placeholder symbols** give each module something to test: `ProtocolVersion` (`current = 4`, `pinnedRelease = "2026.9.6"`, as the Risks section asks), `GatewayDefaults`, `SessionKey.main`, `SharedContainer.appGroupIdentifier`, `LaunchArgument` (`-FakeGateway`, `-DemoConversation`), `Spacing`, and `MarkdownText`, a thin wrapper over Textual's `StructuredText`. Replace or extend them freely in later slices.
- **XcodeBuildMCP session defaults aren't persisted to `.xcodebuildmcp/config.yaml`,** because the project path is an absolute worktree path. Set them each session (see `CLAUDE.md`).

### Tooling quirks found
- **`test_sim` summary undercounts.** It reported `passed: 0` and only listed the UI test, even though all 8 Swift Testing tests passed. Check the `✔ Test run with …` lines in the build log.
- **A full `test_sim` takes about 4.5 minutes,** mostly UI-test runner startup.
- **Disk space ran out during this slice** (`ENOSPC`, even for small shell writes). The owner freed some, but only about 2.1 GB is left after Slice 0, and each build/test cycle adds DerivedData, test products, and result bundles under `~/Library/Developer/XcodeBuildMCP/workspaces/`.

## Slice 2: Device identity, signing, and handshake (2026-09-29)

### Choices the plan left open
- **The connection accepts an injected `DeviceIdentity`; `DeviceIdentityStore` owns Keychain persistence.** This keeps deterministic test keys out of Keychain while the app can call `loadOrCreate()` once at startup. Slice 3 should use the store when it wires onboarding to the connection.
- **Startup `UNAVAILABLE` retries are bounded at three connection attempts**, honoring `retryAfterMs` up to five seconds. General reconnect and network recovery remain Slice 4 work.
- **FakeGateway verifies Ed25519 signatures and returns scripted handshake and RPC responses over a loopback WebSocket.** Tests use this server and never connect to the owner's running Gateway.

## Slice 3: Onboarding and pairing (2026-09-29)

### Choices the plan left open
- **Integration of Slices 3–5 was batched.** GPT 6 Luna agents implemented onboarding, the conversation store, and chat UI in separate files; the coordinator owned socket recovery and app routing. The slice commits separate these concerns; app routing to the new screens lands with Slice 5.
- **Pairing retries use an injected sleeper and elapsed-time provider**, backed by ContinuousClock in the app. The five-minute deadline and cancellation are enforced before each connection attempt. FakeGateway covers pending approval followed by success.
- **TLS fingerprints pin the leaf certificate's SHA-256**, including explicitly trusted self-signed Gateway certificates. Bonjour requests TXT records, treats them as hints, and asks the user to confirm the fingerprint before connecting. Physical-device camera and Bonjour checks remain unverified in this simulator-only pass.
- **Discovery starts when Nearby is selected**, rather than asking for Local Network access on the welcome screen. The scanner reports unavailable camera/permission errors and manual setup remains available in the simulator.

### Verification
- Integrated app and embedded widget build without warnings on iPhone 18 Pro / iOS 27.0. Full test plan: **106 passed, 0 failed**, including setup-code/transport tables, pairing retries, welcome → manual navigation, and FakeGateway manual connect → chat.
- Welcome and chat screenshots checked. `-OnboardingPreview` avoids loading any stored Gateway profile in launch UI tests; `-FakeGateway` and `-DemoConversation` create ephemeral loopback servers and identities.
