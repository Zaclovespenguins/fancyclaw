# Redesign R1: Foundation (theme, tab root, routing, Settings)

Date: 2026-10-02. Plan: `layout_redesign.md`, Slice R1.

## What shipped
- `Design/openclaw-1b/` holds the handoff (no zip). `Design/` is not a synchronized target folder, so the starter Swift files compile into no target.
- `DesignSystem`: `AppTheme` (light/dark tokens, radii, spacing), `ThemeID` (`.coral` only, `@AppStorage("themeID")`), environment value `appTheme`, `AmbientGlow`, glass helper, `sectionHeader()`, `PressScale`, `ProgressLine`, `AgentAvatar`.
- `SystemIntegration/AppRouter.swift`: pure `AppRouter` (selected tab, per-tab paths, `AppRoute`) so routing is unit-tested without views. `AppModel.open(sessionKey:focusApproval:)` replaces `selectSession` for compose, Ask / New Chat / Open Session intents, Live Activity URLs, and approval Review (`AppModel.review`, `AppRouter.reviewApproval`). `invalidateSession` pops chats for deleted sessions and restarts stores for reset ones. `AppModel.conversation` stays as "most recently opened".
- `RootView` (TabView: Home, Chats, Skills, Activity, plus search-role compose tab; per-tab `NavigationStack`). Home, Skills, Activity are placeholders (`TabPlaceholderView`). Chats uses the former drawer list (`SessionsList`); `SessionsDrawer` and `ChatConnectionMenu` were removed.
- `SettingsView`: Connection (status, host, Reconnect, Disconnect with confirmation), Preferences (haptics, same key), Appearance (read-only Theme row), Profile ("Your name"), About (app and Gateway version).

## Choices and deviations
- Settings is opened from a Home placeholder avatar (`home.settings`) until R4.
- Theme row is a read-only `LabeledContent`, not a disabled Picker: a disabled Picker failed the accessibility audit.
- Settings uses a solid theme background rather than the glow, to keep grouped headers readable.
- Added `-DemoOffline` debug mode (connect, then drop and refuse recovery) for the Settings reconnect UI test.
- Chats search field is always shown with inline title (`SessionsList`), so audits see a stable layout.
- Link-previews toggle deferred to R3 as planned.

## Verification (iPhone 18 Pro, iOS 27.0)
- BuildProject (app + extension) and build-for-testing: success, zero errors.
- Full `FancyClaw` plan: 388 passed, 3 failed, 0 skipped (parameterized-expanded). Package targets all passed: Protocol 75, Client 35, ChatCore 73, Persistence 4, DesignSystem 11, TestSupport 11, SystemIntegration 31 (includes 13 AppRouter tests, plus AppTheme tests). UI: 12 passed, 3 failed.
- Failures: `PolishTests` `testChatAndDrawerAccessibility`, `testLargeTextDarkMode`, `testRichOutputAccessibilityAndLargeText`, all "Contrast failed". These three were already failing before R1 (see the 2026-10-02 entries in `plan-deviations.md`); not worsened, not resolved here.
- Result bundle: `/Volumes/SSDCache/Xcode/DerivedData/FancyClaw-bypnjtyvdvflnmctxqlpgdlhnibo/Logs/Test/Test-FancyClaw-2026.10.02_15-41-06--0600.xcresult`. Light/dark and XXL screenshots (Chats tab, Settings offline, chat modes) are retained attachments in that bundle.
- RunAllTests returned an incomplete-bundle error at the MCP limit; results were read with `xcresulttool` after Xcode finished.
- Device checks pending: tab-bar minimize behavior and compose tab on a physical device; iOS 26 unverified.
