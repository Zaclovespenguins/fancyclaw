# Handoff: OpenClaw iOS client (Direction 1b, Dashboard-first)

## Overview
A native iOS client for an OpenClaw agent gateway. The app opens on a **Home dashboard**: a large prompt card, items waiting on the user's approval, running tasks and recent conversations. From Home the user opens **Chat** to talk to the agent ("Claw"). **Skills** lists installed skills/tools, and **Activity** shows a timeline of what the agent has done. The look follows iOS 26 Liquid Glass with an ambient color glow (inspired by Meta's Muse): dark base, floating glass controls, and card-based agent replies.

## About the Design Files
`OpenClaw iOS.dc.html` is a **design reference built in HTML**. It shows the intended look and content. It is not production code. Rebuild the screens in **SwiftUI (iOS 26+)** using native components where they exist (TabView, NavigationStack, List, Toggle, `.glassEffect`). The `SwiftUI/` folder has starter code that follows this README. It compiles as a starting point but uses mock data and no networking.

Open the HTML file in a browser. Direction **1b** is the selected one. Direction 1a (chat-first) is kept for reference only.

## Fidelity
**High-fidelity** for layout, color, type, radii and copy. Where the HTML imitates glass (blur + translucent fill + 0.5pt light stroke + inner top highlight), use real Liquid Glass (`.glassEffect`) instead of copying the CSS. On iOS < 26 fall back to `.ultraThinMaterial`.

Screen size in the mock: 393×852pt (iPhone 16/17 Pro).

## Navigation
- Root: native `TabView` with 4 tabs (**Home, Chats, Skills, Activity**) plus a separate circular **compose** button to the right of the tab bar. On iOS 26 this is `Tab(role: .search)`, which the system draws as a detached glass circle. Selecting it presents a new chat instead of a search screen.
- Tab bar: system Liquid Glass. Use `.tabBarMinimizeBehavior(.onScrollDown)`.
- Each tab has its own `NavigationStack`. Home → tapping the prompt card, a Recent row or a running task pushes `ChatView`.
- Approval "Review" opens the relevant chat, scrolled to the approval card.

## Screens

### 1. Home
**Purpose:** see agent status, start a task, handle approvals, check on running work.

Layout: vertical `ScrollView`, horizontal padding 20pt, starting about 12pt below the safe area. The background is the ambient glow (see Tokens), with content scrolling over it.

1. **Header row** (space-between, bottom aligned)
   - Eyebrow: "THURSDAY, OCT 2". 13pt semibold, uppercase, tracking +0.4, `textSecondary` (60%).
   - Title: "Good evening, Sam". 32pt bold, tracking −0.6, 4pt below the eyebrow. Greeting changes with time of day.
   - Avatar: 40pt circle, glass, initial "S" 16pt semibold. Opens Settings.
2. **Status pill**, 14pt below. Capsule with padding 7/12, glass. 8pt green dot (`online`) with a glow shadow, then "Claw is online · studio-mini" at 13pt, 80% white. Offline: gray dot, "Claw is offline · reconnecting…".
3. **Prompt card**, 20pt below. Corner radius 30, padding 18/16/14, glass (`.regular`), drop shadow 0/20 blur 40 black 30%.
   - Row: agent avatar (26pt) + "Claw" 15pt semibold.
   - Placeholder "What should I take care of?". 22pt medium, tracking −0.2, 42% white, min height 56pt, 12pt below. Tapping it focuses a TextField (multiline, `axis: .vertical`).
   - Bottom row, 10pt below: left is a "+" attach button (36pt circle, 10% white) and a model menu capsule "Opus ⌄" (36pt tall, 13pt semibold). Right is a 36pt solid `#F5F5F7` circle with a waveform glyph (voice). It turns into an up-arrow send button once text is entered.
4. **"Needs you"** section header: 20pt bold, 26pt top margin, 10pt bottom.
   - Approval row. Radius 24, padding 14/16, fill accent at 18% with a 0.5pt stroke in accent at 40%. Title "Push fix to photo-sync" at 16pt semibold. Command `git push origin fix/date-parser` in SF Mono 12.5pt at 60%, one line, truncated. Trailing "Review" capsule 36pt tall, `#F5F5F7` fill, black 15pt semibold.
   - Hide the whole section when there are no approvals.
5. **"Running"**. Horizontal scroll of cards 220pt wide, 10pt gap, radius 24, padding 14/16, glass.
   - Title 15pt semibold. Detail 13pt at 55%. Progress bar 4pt tall, radius 2, track 10% white, fill accent, 14pt above.
   - Content: "photo-sync CI / Patching date parser / 60%", "Flight UA 914 / On time · gate C12 / 35%".
6. **"Recent"**. Inset grouped card, radius 24, 6% white fill, 0.5pt 12% stroke. Rows have padding 12/16: title 16pt semibold (one line), time 13pt at 50%, trailing chevron. Separators are 0.5pt at 10% white.

### 2. Chat
**Purpose:** converse with the agent and act on rich results.

- **Top bar** (custom, floating over content): a 44pt glass back button on the left, a centered agent avatar (30pt) with the conversation title below it (13pt semibold), and a 44pt glass "•••" menu on the right. Content scrolls under a top fade from `bg` at 85% to clear.
- **Messages**, 16pt side padding, 14pt vertical gap:
  - **User bubble**: right-aligned, max width 82%. Radius 22 with a 6pt bottom-right corner. Padding 11/15, 16pt text with line-height 1.38. Fill accent at 32% with a 0.5pt stroke `#F5A07A` at 35%.
  - **Agent text**: no bubble, 16pt, full width.
  - **Tool summary chip**: capsule 34pt tall, 7% white fill. Globe icon, "Browsed 14 listings on 3 sites", chevron. Tapping it expands the tool-call steps.
  - **Link preview card**: radius 22, glass. Image 104pt wide on the left (placeholder in the mock). On the right: title 15pt semibold, meta 13pt at 60%, then favicon (14pt) + domain at 12pt and 45%. Opens in an `SFSafariViewController`.
  - **File card**: radius 20, 7% fill. Doc glyph 34×40, file name 15pt semibold, "Saved to Obsidian · 2 KB" 13pt at 55%, and a 32pt download button. Opens Quick Look / share sheet.
  - **Step progress card** (from 1a, reuse here): header "WORKING · 3 OF 5" 13pt uppercase at 60%, timer on the right. Rows have an 18pt state icon (done = accent filled check, active = spinner, pending = 1.5pt ring) and 15pt text.
  - **Code diff card** (from 1a): file header with +/− counts in green/red mono, then SF Mono 11.5pt lines on a 20pt grid. Added lines get green at 14%, removed lines red at 16%.
  - **Approval card** (from 1a): accent-tinted glass, "APPROVAL NEEDED" eyebrow, title 16pt semibold, command in a mono block (radius 12, black 35%), and "Deny" (10% white) / "Approve" (`#F5F5F7`, black text) buttons, each 40pt tall.
- **Input bar**: floating, 30pt from the bottom, 16pt side insets, 54pt tall capsule, glass. Contains a 40pt "+" button, the placeholder "Ask a follow-up", and a 40pt `#F5F5F7` voice/send button. Use `.safeAreaInset(edge: .bottom)` so it rides above the keyboard.

### 3. Skills
- Large title "Skills" (34pt bold), with a "+" (40pt glass circle) in the toolbar.
- Search field: 40pt capsule, 8% fill, placeholder "Search skills and tools". Use `.searchable`.
- 2-column grid, 10pt gap. Tiles are 132pt tall with radius 24, padding 14 and glass fill.
  - Icon tile 38pt, radius 11, brand color, with a white glyph.
  - Status dot top-right: green when on, 25% white when off.
  - Name 16pt semibold. Tool count 13pt at 50%; disabled tiles add "· Off" and drop to 60% opacity.
- Tapping a tile opens skill detail (not designed yet): toggle, tool list and permissions.
- Skills in the mock: GitHub (14 tools), Shell (3), Browser (9), Calendar (6), Obsidian (5), Gmail (8, off), Home Assistant (12, off), Spotify (7, off).

### 4. Activity
- Large title "Activity". Segmented control "Today / Scheduled" (native `Picker(.segmented)`).
- Timeline: left column with the time (12pt semibold, tabular numbers, 45%, 44pt wide), then the rail (1.5pt line fading from 20% to 4% white), then an 11pt dot with a 3pt `bg` ring and a glow. Event card: radius 20, padding 11/14, glass. Title 15pt semibold, detail 13pt at 55%.
- Dot colors: accent = needs you (card stroke accent at 45%), green = running, 30% white = done.

## Interactions & Behavior
- Glass controls get the press effect from `.glassEffect(.regular.interactive())`. Cards scale to 0.98 on press (spring, response 0.3, damping 0.7).
- Approve/Deny: success haptic (`.sensoryFeedback(.success)`). The card collapses to a one-line receipt ("Approved · pushed fix/date-parser").
- Running progress updates live from the gateway stream. Animate the bar width with `.smooth`.
- Agent text streams token by token. While waiting, show a subtle shimmering "Thinking…" in place of the agent's line.
- The tab bar minimizes on scroll down. The chat input stays visible.
- Pull to refresh on Home and Activity.
- Push notifications for approval requests come with Approve/Deny actions.

## State
- `GatewayConnection`: host name, status (online/connecting/offline), selected model.
- `[Conversation]`: id, title, updatedAt, status (idle/running/needsApproval), messages.
- `Message`: role plus a content enum: `.text`, `.toolSummary`, `.steps`, `.diff`, `.approval`, `.link`, `.file`.
- `[AgentTask]`: title, detail, progress, conversationId.
- `[Skill]`: name, glyph, color, toolCount, isEnabled.
- `[ActivityEvent]`: time, title, detail, kind (needsYou/running/done).
- Data comes from the OpenClaw gateway over WebSocket. The starter uses `MockData`.

## Design Tokens
Colors were converted from OKLCH in the mock, so the hex values are approximate. Match the HTML by eye.
- `bg` #0B0B0F
- `textPrimary` #F5F5F7, `textSecondary` white 60%, `textTertiary` white 45%, `placeholder` white 40%
- `accent` #F28A5E (oklch 0.74 0.16 40), `accentText` #F9A987
- `online` #5CD98A
- `diffAdd` #7EE0A0, `diffRemove` #F08A7A
- Glow: coral #E8613A at 55%, violet #9A6BE0 at 42%, blue #3A8FC8 at 20%. These are radial gradients about 440pt across, fading to clear at 65%, placed top-left, top-right and mid-left.
- Agent avatar: linear gradient 135° from #F8A66A to #E04E3A, with a white bold "C".
- Fallback glass fill: white 7–9%, 0.5pt stroke white 14–18%, inner top highlight white 14–22%.
- Radii: 30 (prompt card), 24 (section cards/tiles), 22 (chat cards, bubbles), 20 (timeline cards), 12 (code blocks), 11/9 (icon tiles), capsules for all buttons.
- Spacing: 20pt screen padding on Home, 16pt elsewhere; 26pt between sections; 10pt within a section's cards.
- Type: SF Pro. 34 bold large titles, 32 bold greeting, 22 medium prompt, 20 bold section headers, 16 body/semibold rows, 15 card titles, 13 meta/eyebrows, SF Mono 11.5–12.5 for code.

## Assets
No bitmaps. Use SF Symbols: `house`, `bubble.left`, `square.grid.2x2`, `waveform.path.ecg`, `square.and.pencil`, `plus`, `waveform`, `arrow.up`, `chevron.right`, `chevron.left`, `ellipsis`, `globe`, `arrow.down.to.line`, `checkmark`, `magnifyingglass`. Skill icons are colored tiles with a letter. Replace them with real brand marks where licensing allows. Link preview images come from each site's OpenGraph image.

## Files
- `OpenClaw iOS.dc.html`: design reference (open in a browser; see section 1b)
- `SwiftUI/`: starter implementation
  - `OpenClawApp.swift`: app entry point and root TabView
  - `Theme.swift`: tokens, ambient glow, glass helpers
  - `Models.swift`: data types and mock data
  - `HomeView.swift`, `ChatView.swift`, `SkillsView.swift`, `ActivityView.swift`
