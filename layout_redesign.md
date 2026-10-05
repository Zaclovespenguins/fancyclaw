# Layout redesign plan (Direction 1b, dashboard-first)

Date: 2026-10-02. Implementation status: R1–R7 are implemented and verified as of 2026-10-04. The final full plan passed 349 tests with no failures or skips, and all four tabs' light/dark default/XXL screenshots were reviewed; evidence is in `.claude/deviations/redesign-r7-activity.md`. This document preserves the design decisions and acceptance criteria.

This replaces FancyClaw's chat-as-root layout with the Claude Design handoff's tabbed, dashboard-first layout: **Home, Chats, Skills, Activity**, plus a compose button. The handoff's SwiftUI starter code is reference only (mock data, no networking). Every screen is rebuilt on the existing stores. Deferred work is in `Future_features.md`.

## Design reference

- Source: the tracked handoff in `Design/openclaw-1b/` (copied in R1 without the `.zip`). That folder isn't a target folder, so the starter Swift files don't compile into the app.
- `Design/openclaw-1b/README.md` has layout, tokens, and copy. `OpenClaw iOS.dc.html` is the visual reference; use section **1b**. Its 1a artboards are reference only, except the cards the README says to reuse.

## Owner decisions (2026-10-02)

| # | Topic | Decision |
|---|---|---|
| 1 | Appearance | Support **light and dark**. Design tokens are the dark variant; define matching light variants. |
| 2 | Skills | **Read-only.** No "+" install or toggles yet (see `Future_features.md`). |
| 3 | Activity | **Placeholder tab** now; live timeline and local cache later (see `Future_features.md`). |
| 4 | Link previews | **Implement.** |
| 5 | Step progress / diff cards | **Leave out** (see `Future_features.md`). |
| 6 | Running cards | **Spinner** while running. No timer, no progress bar. |
| 7 | Home prompt card | Each submit **starts a new chat**. |
| 8 | Agent/model picker | Opens from a **tap on the chat title**. |
| 9 | Settings | **New screen** that takes over the current connection menu; opened from the Home avatar. |
| 10 | Voice / push | Voice button becomes send-only; no push notifications (see `Future_features.md`). |
| 11 | Branding | Agent name and initial come **from the Gateway** (`AgentSummary.name`), not "Claw". The mock's coral accents are the **default theme**, with a **theme picker placeholder** in Settings. |

## Rules for every slice

- **Deviations log.** Don't write deviation entries into `.claude/plan-deviations.md`. Write each deviation, choice the plan left open, and verification result to its own file under `.claude/deviations/` (for example `.claude/deviations/redesign-r2-chat.md`). Then add a one-line pointer under the "Layout redesign" section of `.claude/plan-deviations.md`. Debugging notes still go in `debugging/`.
- **Light/dark.** All colors come from theme tokens with light and dark values; no raw colors in views. In light mode the ambient glow is softer and the base is a warm off-white. Tune both by eye against the mock. Keep the `-PolishLight`/`-PolishDark` launch arguments working.
- **Dynamic Type.** Map the design's point sizes to text styles rather than fixed sizes:

  | Design size | Text style |
  |---|---|
  | 34 bold | `.largeTitle` |
  | 32 bold greeting | `.largeTitle` |
  | 22 medium | `.title2` |
  | 20 bold | `.title3.bold()` |
  | 16 | `.callout` |
  | 15 | `.subheadline` |
  | 13 | `.footnote` |
  | 12 | `.caption` |
  | Mono | `.monospaced()` variants |

  Fixed-size layout values (avatars, button circles) use `@ScaledMetric`. Layouts reflow at accessibility sizes, following the existing `ViewThatFits` / `isAccessibilitySize` patterns.
- **Accessibility.** Keep or replace identifiers used by functional UI tests, and update those tests in the same slice. Accessibility-only audits and repair are deferred at the owner's request; see `.claude/deviations/redesign-accessibility-deferred.md`.
- **Glass.** The deployment floor is iOS 26, so use `.glassEffect` directly and drop the starter's `.ultraThinMaterial` fallback. Use `.interactive()` on tappable glass. Respect Reduce Motion and Reduce Transparency.
- **No new third-party dependencies.** Link previews use Apple's LinkPresentation framework. Textual stays the Markdown renderer.
- **Boundaries.** All CLAUDE.md implementation boundaries still apply: Gateway as source of truth, strict outbound encoding, no attachment bytes in the cache, tests only against `FakeGateway`.
- **Haptics.** The existing `hapticsEnabled` preference (moved into Settings) gates all new haptics.
- **Verification per slice.** Build the app and extension, run focused tests, then the full `FancyClaw` test plan. Take light and dark screenshots at default and XXL text sizes of the screens the slice touched. Record counts and log paths in the slice's deviation file, then commit the slice.

## Current → new map

| New | Replaces / reuses | Backend |
|---|---|---|
| Tab root (`RootView`) | The `ContentView` `NavigationStack` with `ChatView` as the root | `AppModel` routing |
| Home | (new) | `AppModel.status`, `SessionStore`, `ApprovalStore`, `RunActivityStore` |
| Chats tab | `SessionsDrawer` (sheet becomes a tab) | `SessionStore` |
| Chat | `ChatView` and its subviews (restyled) | `ConversationStore`, `ApprovalStore`, `SessionStore` |
| Settings | `ChatConnectionMenu` | `AppModel` reconnect/disconnect, `@AppStorage` |
| Skills | (new) | `SkillStore` and `skills.status` read through the Gateway |
| Activity | (new placeholder) | No data source; `TimelineRow` is preview-only |
| Onboarding, Live Activity, New Chat Control | Unchanged, except restyling Onboarding with theme tokens | Unchanged |

---

## Slice R1: Foundation (theme, tab root, routing, Settings)

**Goal:** the app launches into the new tab shell. The existing `ChatView` still works, pushed from the new routes.

1. **Copy the handoff** into `Design/openclaw-1b/`.
2. **Theme (in `DesignSystem`):**
   - `AppTheme` holds the color tokens from the README (bg, text primary/secondary/tertiary, placeholder, accent, accentText, online, diff add/remove, glow colors), each with a light and a dark value, plus radii and spacing constants.
   - `ThemeID` enum with only `.coral` (the default), stored in `@AppStorage("themeID")`, provided through an environment value. The app-wide `.tint` uses the accent.
   - Views: `AmbientGlow` (adapts to light/dark and Reduce Transparency), `glass(in:tint:interactive:)`, `sectionHeader()`, `PressScale` button style, `ProgressLine` (kept for later).
   - `AgentAvatar(name:)`: gradient circle showing the first letter of the agent name, with a fallback symbol when the name is unknown.
3. **Root:**
   - `RootView` is a `TabView` with Home, Chats, Skills, and Activity tabs plus a `Tab(role: .search)` compose button. It uses `.tabBarMinimizeBehavior(.onScrollDown)`, and each tab has its own `NavigationStack`.
   - The loading state and `OnboardingView` still gate it in `ContentView`. Placeholder content stands in for any tab whose slice hasn't landed yet.
4. **Routing (in `AppModel`):**
   - Add a `selectedTab` and per-tab navigation paths, with a `Route` enum: `.chat(sessionKey, focusApproval: String?)`, `.settings`, `.skill(id)`.
   - `selectSession(_:)` keeps loading and starting the store; a new `open(sessionKey:focusApproval:)` also pushes the chat.
   - Re-point these to `open`: compose button (`newChat()`), the Ask / New Chat / Open Session intents, Live Activity URLs (`openActivityURL`), and approval Review. Intents land on whichever tab is selected, or Home if it's showing a root.
   - `AppModel.conversation` stays as "most recently opened" for intent `ask` compatibility. Chats render whichever store their route names, via `conversationStore(for:)`, which may need to become internal.
5. **Settings screen:**
   - Opened from a toolbar avatar until Home lands in R4.
   - **Connection** section: status with colored dot, Gateway host (from `GatewayProfile.url`), Reconnect (when not connected), Disconnect (destructive, with confirmation).
   - **Preferences** section: Haptics toggle (the existing key), link-previews toggle (added in R3).
   - **Appearance** section: a "Theme" row showing "Coral" with the picker disabled ("More themes coming soon").
   - Optional "Your name" field used by the Home greeting.
   - About: app and Gateway version (`hello.server.version`).
6. **Debug:** existing launch modes still work. `-DemoConversation` opens the seeded chat pushed on Home.
7. **Tests:**
   - Unit-test routing (intent/Live Activity → tab + path).
   - Update the UI tests for the new navigation: drawer → Chats tab, connection menu → Settings.
   - Add a Settings UI test for reconnect/disconnect.

Deviation file: `.claude/deviations/redesign-r1-foundation.md`.

## Slice R2: Chat restyle

**Replaces:** the `ChatView`, `ChatMessageRow`, `ChatToolCard`, `ApprovalCard`, `ChatComposer`, `AgentModelPicker` presentation, and the drawer/connection toolbar items. Store logic is unchanged.

1. **Top bar.**
   - Floating glass back button, a centered `AgentAvatar` with the session title below it, and a glass ••• menu. Content scrolls under a top fade. Hide the navigation and tab bars.
   - **Title tap** opens the agent/model menu (the `AgentModelPicker` sections: "Agent for a new chat", "Model for this chat"). Remove the picker from above the composer.
   - The ••• menu has Rename, Reset, and Delete (with confirmation), all `SessionStore`. Share is deferred.
2. **Messages:**
   - **User bubble:** accent fill with 22-point corners and a 6-point bottom-trailing corner, max width 82%. Keep "Not sent · Retry".
   - **Agent text:** `MarkdownText` without a bubble.
   - **Thinking:** shimmering "Thinking…" (restyled `ChatThinkingIndicator`, static when Reduce Motion is on).
   - **Tool summary chip:**
     - One capsule per assistant message: icon, summary, chevron. The summary comes from the client because the Gateway sends none. One tool shows its name and status ("Ran read_file"); several show "Used 3 tools", with a running/failed state.
     - Expanding it lists each tool, with the existing `ChatToolDetail` arguments/result disclosure.
   - **File card:**
     - Doc glyph, file name, and a detail line (size · type, from `ContentBlock.Media`).
     - The download button fetches through the store's Gateway media path, then opens Quick Look or the share sheet. Nothing is persisted beyond a temporary file.
   - **Images:** `ChatArtifactImage` restyled to 22-point radius cards.
   - **Approval card:**
     - Accent-tinted glass, "APPROVAL NEEDED" eyebrow, title, mono command block.
     - Title is `commandPreview`, else the warning text, else "Run a command". Directory, host, and warning sit in secondary text.
     - Decision buttons come from `offeredDecisions`, including Always allow. Keep expiry, permission, and offline messages.
     - Once resolved, it collapses to a one-line receipt ("Approved · `<command>`" / "Denied" / "Expired" / "Handled elsewhere").
   - **Empty, error, and "Load older" states:** restyled, same behavior.
3. **Input bar:**
   - Floating 54-point glass capsule in `.safeAreaInset(.bottom)`.
   - "+" opens the existing attachment menu (Photo Library, Take Photo, Choose File), with the attachment tray above the capsule.
   - The trailing button is **send** (arrow up), disabled when the draft is empty, and becomes **Stop** while streaming. No waveform.
4. **Approval focus:** `.chat(focusApproval:)` scrolls to `approval:<id>` on appear.
5. **Tests:**
   - Update chat, approval, attachment, and Polish UI tests and their identifiers.
   - Unit-test tool-chip summary text.
   - Take light and dark XXL screenshots of the `-DemoConversation`, `-DemoAttachments`, and `-DemoApprovals` modes.

Deviation file: `.claude/deviations/redesign-r2-chat.md`.

## Slice R3: Link previews

1. **Extraction (ChatCore):**
   - Collect `http`/`https` links from finished (non-streaming) assistant text.
   - Skip Gateway-origin and artifact URLs, which keep their existing image/media handling.
   - Deduplicate, cap at 3 per message, and keep the order they appear in. Pure function, unit-tested.
2. **Metadata (app):**
   - A `LinkPreviewLoader` wraps `LPMetadataProvider`: title, site name / domain, icon, and OpenGraph image.
   - Cache in memory per URL (`NSCache`), never in SwiftData. Timeout plus graceful fallback to a plain domain card.
   - No fetch until the message has finished streaming.
3. **Card:**
   - Glass card with radius 22: a 104-point image on the leading edge (placeholder while loading or missing), title, meta, favicon + domain.
   - Tap opens `SFSafariViewController`; long press shows Copy Link / Share.
   - VoiceOver reads it as one link element.
4. **Setting:**
   - "Show link previews" toggle in Settings, default **on**. When off, no fetch and the inline link stays as is.
   - The toggle exists because previews make the phone contact third-party sites.
5. **Tests:** extraction unit tests. The UI test uses a demo message whose preview loader is stubbed in debug modes, so it makes no network calls.

Deviation file: `.claude/deviations/redesign-r3-link-previews.md`.

## Slice R4: Home

1. **Header:**
   - Date eyebrow and greeting by time of day ("Good morning/afternoon/evening", plus ", <name>" when a name is set in Settings).
   - Avatar button (initial, or a person symbol) opens Settings.
2. **Status pill:**
   - Dot plus "<Agent> is online · <host>" when connected.
   - "Reconnecting…" (amber), or "Offline" (gray) with a tap to reconnect.
   - Agent name comes from the default agent in `SessionStore.agents`; host from the profile URL.
3. **Prompt card:**
   - Agent avatar and name, then a multiline `TextField` ("What should I take care of?").
   - Bottom row: "+" attach, model menu capsule (`SessionStore.models`, defaulting to the Gateway default), and send.
   - **Submit:** `sessions.create`. If a model other than the default was picked, `setModel` on the new session. Then open the chat route and `send(text, attachments)`.
   - A failure keeps the draft and shows an `ErrorBanner`. The draft and attachments live in a small Home draft model that isn't persisted.
4. **Needs you:**
   - Shown only when there are pending approvals. Rows from `ApprovalStore.approvals` with status pending: same title rule as R2, mono command (one line), "Review".
   - Review opens `.chat(sessionKey, focusApproval: id)`. If the approval has no session key, Review opens a sheet with the full approval card instead.
5. **Running:**
   - Horizontal cards for sessions with an active run, from `SessionSummary.hasActiveRun`/`activeRunIds` merged with `RunActivityStore` runs.
   - Each card shows the session title and a detail line: the run status label ("Thinking", "Replying"), plus "Waiting on you" when approvals are pending.
   - A **spinner** stands in for the progress bar. Tap opens the chat. Hidden when nothing is running.
6. **Recent:** first 5 of `SessionStore.visibleSessions` (title plus relative time), each opening the chat; "See all" switches to the Chats tab.
7. **Pull to refresh** calls `AppModel` resync. The offline state shows cached sessions with a reconnect affordance.
8. **Tests:**
   - Unit tests for greeting, the running-row merge, and the approval title rule.
   - UI tests: prompt → new chat with the message sent (FakeGateway), approval Review → focused chat, Recent → chat.
   - Add a `-DemoHome` launch mode seeding approvals, a running session, and history.

Deviation file: `.claude/deviations/redesign-r4-home.md`.

## Slice R5: Chats tab

**Replaces:** `SessionsDrawer` (the sheet is removed).

- Large-title "Chats" list in theme styling, keeping all drawer behavior:
  - Pinned / Today / Yesterday / Earlier groups, `.searchable`, load more, and pull to refresh.
  - Swipe actions and context menu (Rename / Reset / Delete with confirmation), empty and search-empty states, error banner.
- Rows (from 1a's History artboard): title, time, two-line preview, status chip. "Running" (green) when `hasActiveRun`; "Needs approval" (accent) when `ApprovalStore.pendingCount(for:) > 0`, replacing the terminal-count badge.
- Toolbar compose button creates a new chat; it's the same action as the tab bar compose button.
- Tests: migrate the drawer's functional UI coverage (identifiers `sessions.*`). Accessibility-only audits are deferred per `.claude/deviations/redesign-accessibility-deferred.md`.

Deviation file: `.claude/deviations/redesign-r5-chats.md`.

## Slice R6: Skills (read-only)

1. **Protocol:**
   - Capture `skills.status` (and `tools.catalog` if it's needed for tool counts) from a throwaway Gateway or the pinned package schema. Ask the owner before any `.live` run.
   - Add the shapes to `DEFINITIONS` in `Scripts/refresh-protocol-schema.mjs` and refresh the fixture subset.
   - Model them tolerantly in `GatewayProtocol`, encode params strictly.
   - Both are `operator.read`, which the app already requests.
2. **Store:**
   - `SkillStore` (ChatCore, `@MainActor @Observable`) handles load, refresh on reconnect, search filter, and error state.
   - Tile model: name, description, emoji/letter glyph, brand color from a small known-skill map (else a neutral derived color), tool count if available, and enabled/eligible state.
3. **UI:**
   - Large title "Skills" with `.searchable` ("Search skills") and a two-column grid of glass tiles with status and availability. Tool counts and skill-to-tool associations are not reported by `skills.status` and are omitted.
   - No "+" and no toggles.
   - Tile tap shows a minimal read-only detail sheet (description, status, requirements/missing items, and source facts). The full detail screen and tool list are deferred.
   - Empty, error, and offline states.
4. **Tests:**
   - Decoding tests from fixtures, including unknown fields and values.
   - Store tests with FakeGateway `skills.status` handling.
   - UI test for grid, search, and detail; light/dark XXL screenshots.

Deviation file: `.claude/deviations/redesign-r6-skills.md`.

## Slice R7: Activity placeholder

- Large title "Activity", a native segmented control (Today / Scheduled), ambient background.
- Each segment shows a `ContentUnavailableView`-style placeholder ("Activity is coming soon"). Today: "A timeline of approvals, runs and replies will appear here." Scheduled: "Scheduled jobs from your Gateway will appear here."
- Add the timeline row (`TimelineRow`) as a preview-only component, so the later implementation in `Future_features.md` starts from it. Not wired to data.
- Tests: `ActivityTests.testTodayAndScheduledPlaceholders` checks both segment states. `ActivityTests.testActivityScreenshotsBothSegmentsLightDarkDefaultAndXXL` captures both segments at light/dark and default/XXL (eight attachments). Accessibility audits are deferred per `.claude/deviations/redesign-accessibility-deferred.md`.
- **Final redesign pass** (in this slice, after the placeholder):
  - Full test plan.
  - Light and dark screenshots at default and XXL text sizes for every tab. Home, Chats, Skills, and Activity retain screen-local screenshot tests; the root owns the final all-tabs screenshot review.
  - Update `CLAUDE.md` Current status and Layout sections with the implemented app structure.

Deviation file: `.claude/deviations/redesign-r7-activity.md`.

---

## Risks and notes

- **Routing refactor (R1) is the riskiest change.** Intents, Live Activity URLs, and session invalidation (`invalidateSession`) all assume one active conversation. Cover them with unit tests before restyling anything.
- **Tab bar vs. chat input.** The chat hides the tab bar while pushed. Confirm keyboard avoidance and the minimize-on-scroll behavior on iOS 27, and on iOS 26 if a runtime becomes available.
- **Light-mode glow and glass.** Their contrast needs on-device judgment. The audit catches text contrast but not aesthetics.
- **Agent name.** Gateway agents may have no `name`. Fall back to the capitalized `agentId`, matching `RunActivityStore`.
- **Device checks still pending:** the existing list in CLAUDE.md, plus link-preview fetching on a real network.
