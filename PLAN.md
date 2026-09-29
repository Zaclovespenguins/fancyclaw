# FancyClaw — a polished, Apple-native iOS client for OpenClaw

## Context
OpenClaw's official iOS app works but feels utilitarian. FancyClaw is a personal/TestFlight iPhone app that talks to a single OpenClaw Gateway as an **operator** (chat client, not a device node), with UI inspired by the Claude and Meta Muse iOS apps and a codebase that reads like Apple sample code: SwiftUI-first, Swift 6 strict concurrency, Observation, SwiftData, CryptoKit, Network.framework, App Intents, WidgetKit/ActivityKit, Swift Testing. There is one third-party dependency: **[Textual](https://github.com/gonzalezreal/textual)**, for Markdown rendering. SwiftUI has no native block-level Markdown renderer; `AttributedString(markdown:)` handles inline styles only.

Working directory `/Users/server/projects/fancyclaw` is empty (greenfield, not yet a git repo).

### Decisions (from Q&A)
| Topic | Decision |
|---|---|
| Min OS | **iOS 26**, iPhone only (Liquid Glass, `glassEffect`, native `WebView`, `@Observable`, SwiftData) |
| Role | Operator chat client only (no node role, no camera/location commands) |
| Network | Tailscale (Serve `wss://*.ts.net` or tailnet `ws://`), LAN via Bonjour, public HTTPS reverse proxy |
| v1 extras | Attachments & rich output (Markdown, code, images, tool cards); App Intents/Shortcuts, widget, Control, Live Activity |
| Out of v1 | Voice/Talk, push notifications (APNs), multi-gateway, iPad/Mac/Watch |
| Persistence | Gateway = source of truth; SwiftData cache for instant launch + offline read |
| Approvals | Inline exec-approval cards (Approve / Deny) |
| Protocol layer | **Own Apple-native layer**; hand-written Codable models for only what we use, validated against fixtures from the official schema |
| Name | FancyClaw, bundle id `com.<you>.fancyclaw` (confirm team/prefix in Slice 0) |

---

## Protocol reference (pinned to OpenClaw **v2026.9.6**, protocol **v4**)
All facts below come from `github.com/openclaw/openclaw` `main` / docs.openclaw.ai as of 2026-09-29. **Pin to tag `v2026.9.6`**; the protocol moves fast.

Key sources (raw): `docs/gateway/protocol/{transport,handshake,auth,versioning,rpc-session-control,rpc-bootstrap-and-events}.md`, `docs/gateway/{remote,tailscale,bonjour,pairing}.md`, `docs/cli/qr.md`, schema `packages/gateway-protocol/src/schema/{frames,logs-chat,sessions-*}.ts`, `packages/gateway-protocol/src/client-info.ts`, `packages/gateway-client/src/device-auth.ts`, reference Swift impl `apps/shared/OpenClawKit/Sources/OpenClawKit/{GatewayChannel,DeviceIdentity,DeepLinks}.swift`.

### Transport
- One port (default **18789**) serves WS + HTTP. WS endpoint is the root (`wss://host[:port]/`), optional path prefix behind proxies (setup code may carry `contextPath`). `GET /healthz` for reachability probes.
- Text frames of JSON. Pre-auth payload cap 64 KiB; post-auth use `hello-ok.policy.maxPayload` (default 25 MiB).
- `ws://` only allowed for loopback/LAN/link-local/`.local`/`.ts.net`/Tailscale CGNAT (100.64/10); everything else **must be `wss://`**. Enforce the same rule client-side (and in ATS: `NSAllowsLocalNetworking` + per-domain exceptions for `ts.net`).
- Frames (closed schemas — **never send extra fields**):
  ```
  req   {type:"req", id, method, params?}
  res   {type:"res", id, ok, payload?, error?:{code,message,details?,retryable?,retryAfterMs?}}
  event {type:"event", event, payload?, seq?, stateVersion?}
  ```
- Error codes: `NOT_LINKED, NOT_PAIRED, AGENT_TIMEOUT, INVALID_REQUEST, FORBIDDEN, APPROVAL_NOT_FOUND, UNAVAILABLE`. `FORBIDDEN` + `details.code:"MISSING_SCOPE"` carries `missingScope`.

### Handshake
1. Open socket → server sends `{"type":"event","event":"connect.challenge","payload":{"nonce":"…","ts":<ms>}}`.
2. Client sends `connect` req as the **first** frame:
   ```json
   {"type":"req","id":"<uuid>","method":"connect","params":{
     "minProtocol":4,"maxProtocol":4,
     "client":{"id":"openclaw-ios","displayName":"FancyClaw","version":"1.0.0","platform":"ios",
               "deviceFamily":"iPhone","modelIdentifier":"iPhone17,1","timeZone":"America/Denver","mode":"ui"},
     "role":"operator","scopes":["operator.read","operator.write","operator.approvals"],
     "caps":["tool-events","chat-only-assistant-text","session-scoped-events","approvals","exec-approvals"],
     "auth":{"token":"<deviceToken | sharedToken>"},   // or "bootstrapToken" / "password"
     "locale":"en-US","userAgent":"FancyClaw/1.0.0 (iOS 26.0)",
     "device":{"id":"<hex sha256(rawPubKey)>","publicKey":"<b64url raw 32B>","signature":"<b64url>",
               "signedAt":<challenge.ts>,"nonce":"<challenge.nonce>"}}}
   ```
   `client.id` and `client.mode` are **closed enums** (`client-info.ts`), and unknown ids are rejected (see "Client identity" below).
   After connecting with a setup-code `bootstrapToken`, persist the operator entry from `hello-ok.auth.deviceTokens[]` and use it as `auth.token` on later connects.
3. Server replies `res` with `payload.type:"hello-ok"`: `protocol`, `server{version,connId}`, `features{methods,events}`, `snapshot{presence,health,sessionDefaults,…}`, `auth{role,scopes,method,deviceToken?,deviceTokens?}`, `policy{maxPayload,maxBufferedBytes,tickIntervalMs(15000),attachments{maxBytes,maxImageBytes}}`.
4. `UNAVAILABLE` with `details.reason:"startup-sidecars"` + `retryAfterMs` → retry after delay.

### Device identity & signing
- Ed25519 via `CryptoKit.Curve25519.Signing.PrivateKey`; private key stored in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- `device.id` = lowercase hex SHA-256 of raw 32-byte public key. `publicKey`/`signature` are **base64url (no padding)**.
- Signature payload (UTF-8, `|`-joined). Use **v3** (preferred; v2 also accepted):
  `v3|deviceId|client.id|client.mode|role|scopes(comma-joined)|signedAtMs|token|nonce|platform|deviceFamily`
  (`platform`/`deviceFamily` trimmed, ASCII-lowercased; `token` = the `auth.token` being sent, or bootstrap token, or empty; `signedAt` = challenge `ts`).
- Auth token precedence: explicit shared token → stored device token (per deviceId+role) → bootstrapToken.
- Persist `hello-ok.auth.deviceToken` (+ scopes) in Keychain — **only when connected over `wss://` or loopback**.
- Error `details.code` to map to UI: `DEVICE_AUTH_*`, `AUTH_TOKEN_MISMATCH` (`canRetryWithDeviceToken`), `AUTH_SCOPE_MISMATCH`, `OPERATOR_ACCESS_DENIED`, `PAIRING_REQUIRED` (`recommendedNextStep:"wait_then_retry"`).

### Pairing / onboarding paths
1. **Setup code / QR** (`openclaw qr`, or Control UI → Devices → Pair device): base64url JSON `{url, urls?, tlsFingerprint?, expiresAtMs?, bootstrapToken?, token?, password?}` (or `{host,port?,tls?,…}`). Scan with VisionKit `DataScannerViewController` or paste. Bootstrap tokens expire in 10 min.
2. **Bonjour**: `NWBrowser` for `_openclaw-gw._tcp` in `local.`; TXT keys `displayName, lanHost, gatewayPort, gatewayTls, gatewayTlsSha256, tailnetDns`. TXT is an unauthenticated hint — show fingerprint and require user confirmation (TOFU pin). Needs `NSBonjourServices` + `NSLocalNetworkUsageDescription`. (Bonjour advertising is opt-in on non-mac hosts: `openclaw plugins enable bonjour`.)
3. **Manual**: URL + token/password.
- After a first connect from a non-loopback device, the Gateway returns `PAIRING_REQUIRED`; a third-party client may need a manual `openclaw devices list` → `openclaw devices approve <requestId>`. Requests expire in 5 min. UI shows a "Waiting for approval" screen that copies the command and auto-retries with backoff.

### Liveness
- `tick` event every `tickIntervalMs`; treat >2× interval without tick as dead → reconnect.
- Track event `seq`; on gap, resync (re-fetch history/session list).
- `shutdown {reason, restartExpectedMs?}` → show banner, reconnect after delay.

### Operator methods used
- `chat.send {sessionKey, message, idempotencyKey, attachments?, thinking?, queueMode?}` → `{runId, status:"started"}`
- `chat.history {sessionKey, cursor?, limit?}`; catch-up returns `{kind:"delta", messages, deltaCursor}` or `{kind:"reset"}`
- `chat.abort {sessionKey, runId?}`
- `sessions.list`, `sessions.subscribe`, `sessions.patch`, `sessions.reset {key}`, `sessions.delete`, `sessions.create`
- `agents.list`, `models.list {view:"configured"}`, `status`, `health`
- `exec.approval.resolve` / `approval.resolve` (needs `operator.approvals`)
- Events: `chat` (state `status|delta|final|aborted|error`; `delta` has `deltaText`, optional full-snapshot `message` + `replace`), `agent` (tool/lifecycle streams; with `chat-only-assistant-text` cap, assistant text comes **only** via `chat`), `sessions.changed`, `exec.approval.requested/resolved`, `tick`, `shutdown`, `presence`, `health`.
- Streaming rule: render assistant text from `chat` only; tool cards from `agent` tool stream. On `delta` with `message` (snapshot) or `replace:true`, **replace** buffer, never append twice.

### Exact payload shapes (verified in source)
**Sending** (mirror `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+Sending.swift`): generate `localRunId = UUID().uuidString`, send it as `idempotencyKey`; optimistic user echo id `"\(localRunId):user"`. On ack, if `response.runId != localRunId` adopt the server `runId`. Confirm the optimistic message by matching `idempotencyKey` on messages in canonical history. Outbox retries reuse the same key (idempotent).

**Attachments** (`logs-chat.ts`): `{type?, mimeType?, fileName?, origin?:"paste"|"file", content?:<base64>, sizeBytes?, width?, height?, durationMs?}`. Keep each file ≤ `policy.attachments.maxBytes` (images ≤ `maxImageBytes`) and the total frame ≤ `maxPayload`. Images in history come back as **URLs/`artifactId`** (short-lived, e.g. `/api/chat/media/outgoing/…/full`), not base64. Load them with authenticated fetch or `artifacts.download`, and never cache the image bytes in the transcript store.

**chat.history response**: `{sessionKey, sessionId?, messages[], sessionInfo{key,agentId,hasActiveRun,activeRunIds}, inFlightRun?, hasMore?, nextOffset?, deltaCursor?}`. Page older messages with `offset`/`nextOffset` while `hasMore`. For catch-up, pass `cursor: deltaCursor` → `{kind:"delta",…}` or `{kind:"reset"}`. The server resets after 200 events or 1 MB, so the fallback is a tail refetch; that tail refetch is what the official app does.
- Message: `{role, content[], timestamp(ms), model?, toolCallId?, toolName?, usage?, stopReason?, errorMessage?, isError?, idempotencyKey?, __openclaw?{id, runId, kind, …}}`. `__openclaw.id` is the stable entry id, used for identity and SwiftData keys.
- Content block `type`: `text`, `thinking`, `toolCall` (also accept `tool_use`/`tooluse`/`tool_call`), `image`, `audio`, `video`, `file`. Fields: `text, thinking, mimeType, fileName, artifactId, url, alt, width, height, sizeBytes, id, name, arguments, details, isError`. Tool results arrive as separate messages carrying `toolCallId`/`toolName`.

**agent event** `{runId, seq, stream, ts, sessionKey?, agentId?, data}`. Tool events are sent only if we advertise the `tool-events` cap.
- `stream:"tool"`: `{phase:"start", name, toolCallId, parentToolCallId?, args}` · `{phase:"update", name, toolCallId, partialResult}` · `{phase:"result", name, toolCallId, meta, isError, toolErrorSummary?, result}`
- `stream:"lifecycle"`: `{phase:"start", startedAt}` · `{phase:"end"|"error"|"finishing", error?, stopReason?, aborted?, endedAt}`. This stream drives the Live Activity.
- Ignore the other streams for v1 (thinking, plan, usage, …) and decode them as `.unknown`.

**sessions.list** params we use: `{limit, offset, search?, includeDerivedTitles:true, includeLastMessage:true, excludeSubagents:true, excludeCron:true, excludeSystem:true}`. Response: `{sessions:[SessionRow], hasMore, nextOffset, totalCount}`.
- SessionRow (open object, decode tolerantly): `key, sessionId?, agentId?, label?, displayName?, derivedTitle?, lastMessagePreview?, updatedAt?, lastActivityAt?, status?, model?, pinned?, unread?, archived?`, plus `hasActiveRun`.
- Title precedence: `label → displayName → derivedTitle → "New chat"`.

**sessions.patch** `{key, label?, pinned?, unread?, model?, thinkingLevel?}`. These fields need `operator.write`; archiving also requires `expectedSessionId`.

**sessions.changed**: `{sessionKey, reason, ts, session?, sessionId?}`. If `session` is present, upsert it. If the event has no row, refetch the list. A delete carries the removed `sessionId`.

**models.list** `{view:"configured"}` → `{models:[{id,name,provider,alias?,available?,reasoning?,thinkingLevels?}], defaultModels?}`.
**agents.list** → `{defaultId, mainKey, agents:[{id,name?,identity?,model?,kind?}]}`. The default session key for the main agent is `agent:main:main`.

**Approvals** (`approvals.ts`, `exec-approvals.ts`, `src/infra/exec-approvals-core.ts`)
- Event `exec.approval.requested`: `{id, createdAtMs, expiresAtMs, request:{command, commandPreview?, cwd?, host?, warningText?, allowedDecisions?, unavailableDecisions?, agentId?, sessionKey?, runId?, toolCallId?}}`
- Event `exec.approval.resolved`: `{id, decision, resolvedBy?, ts}`
- Resolve with `exec.approval.resolve {id, decision}` → `{ok:true}`. `decision` ∈ `"allow-once" | "allow-always" | "deny"`; show only the options in `allowedDecisions` (deny is always allowed). Unknown or expired `id` → error `APPROVAL_NOT_FOUND`, which we show as "already handled".
- Plugin approvals (`plugin.approval.requested/resolved`, `plugin.approval.resolve`) use the same envelope with a `{title, description, severity}` presentation. Supporting them reuses the same card.
- Requires the `operator.approvals` scope. The expiry countdown uses `expiresAtMs`.

---

## Architecture

```
FancyClaw.xcodeproj  (Xcode 27.2, iOS 27 SDK, deployment target iOS 26, folder-synchronized groups → no pbxproj edits per file)
├─ FancyClaw/                App target (SwiftUI, @main, scenes, feature views)
├─ FancyClawWidgets/         Widget extension (widget, Control, Live Activity UI)
├─ Packages/FancyClawKit/    Local Swift package (all testable logic)
│   ├─ GatewayProtocol       Codable frames + models, JSONValue, error codes (pure, no I/O)
│   ├─ GatewayClient         actor GatewayConnection (URLSessionWebSocketTask), DeviceIdentity (CryptoKit),
│   │                        Keychain store, handshake/sign, request/response correlation, event AsyncStreams,
│   │                        reconnect/backoff, tick watchdog, NWPathMonitor, Bonjour NWBrowser, SetupCode parser
│   ├─ ChatCore              @Observable stores: SessionStore, ConversationStore (streaming reducer),
│   │                        ApprovalStore, AttachmentPipeline; outbox with idempotency keys
│   ├─ Persistence           SwiftData @Model cache (CachedSession, CachedMessage), ModelContainer factory
│   ├─ DesignSystem          Colors/typography tokens, glass components, FancyClaw Textual style + code block chrome, tool card
│   └─ TestSupport           FakeGateway (NWListener WebSocket server), fixture loader, frame recorder
└─ FancyClawTests / FancyClawUITests   (Swift Testing + XCUITest)
```

Principles: Swift 6 language mode, strict concurrency; `actor` for the socket; `@MainActor @Observable` stores injected via `.environment`; `AsyncStream` for events; `os.Logger` with subsystems; `Duration`/`ContinuousClock` injectable for deterministic tests; errors as typed `enum GatewayError: LocalizedError`. No Combine, no singletons except the `ModelContainer`.

### UI language (Claude + Muse inspiration)
- **Root**: `NavigationStack` chat screen; leading toolbar button opens the **session drawer** (a sheet with `.presentationDetents` on iPhone, like Claude's sidebar) listing sessions grouped by date with `.searchable`.
- **Chat**: full-bleed transcript, user messages in soft tinted rounded bubbles right-aligned; assistant messages **un-bubbled**, full-width typographic text (Claude style) rendered with Textual's `StructuredText(markdown:)`. A custom `StructuredText.Style` adds font-scaled spacing, Liquid Glass code-block chrome (language label, copy button, horizontal scroll, syntax highlighting), tables, lists and images, and turns on `.textual.textSelection(.enabled)`. User bubbles use `InlineText(markdown:)`.
- **Composer**: floating Liquid Glass capsule (`.glassEffect(.regular.interactive())`) pinned via `safeAreaInset(edge: .bottom)`, with attach (+) menu, multi-line `TextField(axis: .vertical)`, send ↔ stop morphing button (`contentTransition(.symbolEffect(.replace))`), agent/model pill above like Muse's mode chip.
- **Streaming**: text fades in per chunk (`.transition(.opacity)` + `phaseAnimator` shimmer "thinking" indicator); tool calls render as collapsible glass cards with SF Symbol + status (`symbolEffect(.pulse)` while running).
- **Approvals**: inline card with command preview, Approve (prominent glass) / Deny, `sensoryFeedback`.
- **Onboarding**: 3 steps in a `TabView(.page)`: Welcome → Connect (Scan QR / Nearby / Manual) → Waiting for approval → done, with `MeshGradient` hero background.
- **Settings**: native `Form` (connection info, fingerprint, scopes, sign out/forget device, appearance, haptics).
- Dynamic Type, VoiceOver labels, Reduce Motion respected everywhere; dark/light parity.

---

## Vertical slices
Each slice ends with: build green (`build_sim`), all tests green (`test_sim`), and a screenshot/`snapshot_ui` check for UI slices. Commit after each slice.

### Slice 0 — Project skeleton & tooling
- `git init`; create Xcode 27 iOS App project "FancyClaw" (SwiftUI, Swift Testing, iOS 26 deployment, Swift 6), widget extension target, local package `Packages/FancyClawKit` with the empty modules above. Add the SwiftPM dependency `https://github.com/gonzalezreal/textual` pinned `.upToNextMinor(from: "0.5.0")`, since it's pre-1.0 and minor versions may break. Only `DesignSystem` depends on it; it requires iOS 18+ and Swift tools 6.0, and brings in `swift-concurrency-extras` and `swiftui-math`. Use XcodeBuildMCP project scaffolding if enabled; otherwise create in Xcode once. Add `.gitignore`, `CLAUDE.md` (conventions + XcodeBuildMCP commands), Info.plist keys (Local Network, Bonjour services, Camera for QR, ATS local networking).
- App shows a placeholder `ContentView`.
- **Tests**: 1 trivial Swift Testing test per module; one UI test launching app.
- **Verify**: `session_show_defaults` → `session_set_defaults` (project, scheme FancyClaw, iPhone 18 Pro sim on iOS 27.0; optionally add an iOS 26 runtime to check the deployment floor) → `build_run_sim` → `screenshot`.

### Slice 1 — Protocol models + fixtures
- `GatewayProtocol`: `RequestFrame`, `ResponseFrame`, `EventFrame`, `GatewayErrorShape`, `JSONValue`, `ConnectParams`, `HelloOK`, `ConnectChallenge`, `ChatEvent` (discriminated on `state`), `ChatSendParams/Response`, `ChatHistory*`, `SessionSummary`, `ExecApprovalRequest`, error-code enums (unknown values tolerated via `.unknown(String)`).
- Fixtures: copy example JSON frames from the docs + a snapshot of `dist/protocol.schema.json` (built from tag v2026.9.6 via `pnpm protocol:gen`, or pulled from npm `@openclaw/gateway-protocol@2026.9.6`) into `TestSupport/Fixtures/`.
- **Tests**: round-trip decode/encode every fixture; encoder emits **no extra keys** (compare key sets against schema `properties` for closed objects); unknown event names/states decode without throwing.

### Slice 2 — Device identity, signing, handshake against FakeGateway
- `DeviceIdentity` (CryptoKit Ed25519, Keychain), `base64url`, `deviceId` derivation, v3 signature payload builder.
- `FakeGateway` in TestSupport: `NWListener` + `NWProtocolWebSocket`, scriptable (send challenge, assert connect params, verify signature with public key, reply hello-ok or error).
- `GatewayConnection` actor: connect → await challenge → send connect → await hello-ok; request/response correlation by id with timeout; event `AsyncStream`.
- Encode the client identity constants (`openclaw-ios` / `ui`; see "Client identity").
- **Tests**: known-vector test for deviceId + signature payload string (hard-code a test key); handshake happy path; `PAIRING_REQUIRED`, `AUTH_TOKEN_MISMATCH`, `UNAVAILABLE startup-sidecars` retry; pre-auth frame > 64 KiB never sent.
- **Optional live check**: `openclaw gateway --bind loopback` locally with a test token from a local `.env.example`, integration test tagged `.live` (disabled by default).

### Slice 3 — Onboarding & pairing UI (manual + setup code + Bonjour)
- `SetupCode` parser (base64url JSON, both shapes, expiry), QR scanner (`DataScannerViewController` in `UIViewControllerRepresentable`), paste from clipboard (`PasteButton`), Bonjour `NWBrowser` "Nearby" list, manual form.
- Transport policy: reject `ws://` to non-private hosts; TOFU fingerprint confirmation sheet; TLS pin check via `URLSessionDelegate` when `tlsFingerprint` present.
- "Waiting for approval" screen: shows `openclaw devices approve` guidance with copy button; retries with backoff until approved or 5-min expiry.
- Persist gateway profile (URL, fingerprint, device token) in Keychain; app routes to chat when paired.
- **Tests**: parser tests (valid/expired/malformed); URL policy table test; onboarding state machine tests with FakeGateway (pending → approved); UI test: manual connect to FakeGateway launched via launch argument `-FakeGateway` → lands on chat screen.

### Slice 4 — Connection lifecycle & resilience
- Reconnect with exponential backoff + jitter, tick watchdog (2× interval), `seq` gap detection → resync, `shutdown` handling, `NWPathMonitor` + `scenePhase` (disconnect on background, reconnect on foreground), connection status pill in the nav bar (glass capsule: Connected / Reconnecting / Offline).
- **Tests**: with injected clock: missed ticks trigger reconnect; seq gap triggers resync callback; backoff sequence bounded; shutdown with `restartExpectedMs` waits then reconnects.

### Slice 5 — Streaming chat (text only)
- `ConversationStore`: send (`chat.send` with UUID `idempotencyKey`), optimistic user message, streaming reducer for `chat` events (`delta` append / snapshot-replace, `final`, `aborted`, `error` with `errorKind` copy), stop button → `chat.abort`.
- Chat view + composer per UI spec; auto-scroll with `ScrollPosition`, `defaultScrollAnchor(.bottom)`.
- **Tests**: reducer unit tests from recorded event sequences (incl. replace/snapshot, duplicate delta, out-of-order final); FakeGateway integration: send → deltas → final renders full text; abort path; UI test types a message and sees streamed reply.

### Slice 6 — History, sessions drawer, SwiftData cache
- `chat.history` paging on scroll-to-top; delta catch-up on reconnect using `deltaCursor` (`reset` → refetch).
- `SessionStore`: `sessions.list` + `sessions.subscribe` / `sessions.changed`; drawer with search, new chat (`sessions.create`), rename (`sessions.patch` label), reset, delete (swipe actions + confirmation dialog). Agent/model picker pill (`agents.list`, `models.list`, `sessions.patch`).
- SwiftData cache: write-through on history/session fetch; cold launch renders cache instantly, then reconciles.
- **Tests**: in-memory `ModelContainer` tests for upsert/reconcile; pagination cursor tests; drawer UI test (create, rename, delete).

### Slice 7 — Rich output: Markdown, code, tool cards
- **Textual does the Markdown parsing and rendering; don't write a custom parser.** Assistant messages use `StructuredText(markdown:)`, styled by a `FancyClawStructuredTextStyle` in `DesignSystem`. The style covers:
  - headings, lists, blockquotes, tables and inline code
  - code blocks with a language label, copy button, horizontal scroll and a light/dark highlighter theme
  - links opened with `openURL`
  - `.math` syntax extension turned on
- **Images:** gateway artifact image URLs are relative and short-lived, so resolve them against the gateway base URL and load them with authentication before Textual renders them. If Textual's image loading can't take custom headers, render `image` content blocks as separate SwiftUI views instead.
- **Streaming:** Textual's docs don't mention incremental rendering. Re-render the growing string on each delta, throttle UI updates to about 30 Hz, and check that an unclosed code fence or a half-written table renders cleanly mid-stream.
- Tool cards from the `agent` tool stream: running/success/error, expandable args and result, monospaced.
- **Tests:**
  - Our own code: the message → Markdown-string mapping (text blocks joined, thinking blocks excluded) and the artifact URL resolver.
  - Tool-event reducer tests.
  - A throttle test using the injected clock.
  - `snapshot_ui` and screenshot checks on a seeded fixture conversation (launch arg `-DemoConversation`) covering a table, nested list, fenced code, math, and a partial stream in progress.
  - We don't unit-test Textual's parser.

### Slice 8 — Attachments
- `+` menu: `PhotosPicker`, camera (`UIImagePickerController` wrapper), `fileImporter`. Attachment tray with thumbnails above composer.
- Pipeline: downscale/HEIC→JPEG via ImageIO to fit `policy.attachments.maxImageBytes`, enforce `maxBytes`, base64 into `chat.send.attachments`.
- **Tests**: size-limit enforcement, MIME detection, encoding shape vs fixture; FakeGateway asserts received attachment payload.

### Slice 9 — Exec approvals
- `ApprovalStore` listens to `exec.approval.requested/resolved`; inline card in the relevant session + badge on other sessions; Approve / Deny via `exec.approval.resolve`; handle `APPROVAL_NOT_FOUND` (already resolved elsewhere) gracefully; request `operator.approvals` scope (handle `MISSING_SCOPE` with explanatory UI).
- **Tests**: store tests (request → resolve locally → resolved event idempotent); FakeGateway round-trip; UI test taps Approve.

### Slice 10 — System integration: App Intents, widget, Control, Live Activity
- App Intents: `AskFancyClawIntent` (text param → sends to default session, returns reply when app foreground / opens app), `NewChatIntent`, `OpenSessionIntent` with `SessionEntity` (`AppEntity` + `EntityQuery` from SwiftData cache); `AppShortcutsProvider` phrases for Siri/Spotlight.
- Widget: "Recent chats" (reads shared SwiftData via App Group) + Control Center `ControlWidgetButton` "New chat".
- Live Activity (ActivityKit) while a run is streaming: agent name, elapsed time, status; ends on final/abort. Updated locally (no push in v1).
- **Tests**: intent `perform()` unit tests with fake stores; entity query tests; Live Activity attribute/state encoding tests; build the widget target.

### Slice 11 — Polish pass
- Haptics (`sensoryFeedback`), empty states (`ContentUnavailableView`), error banners, accessibility audit (XCUITest `performAccessibilityAudit()`), Dynamic Type XXL screenshots, dark mode screenshots, app icon (Icon Composer layered icon), launch performance check.
- **Tests**: accessibility audit UI test passes; no warnings under strict concurrency.

---

## Client identity (resolved)
`client.id` and `client.mode` are closed enums in `packages/gateway-protocol/src/client-info.ts`, so we **send `client.id:"openclaw-ios"`, `mode:"ui"`**, the same values as the official app's operator connection. FancyClaw's own identity goes in `displayName:"FancyClaw"` and `userAgent`. Avoid the other values:
- `webchat`: uses browser-origin handling.
- `gateway-client`/`backend`: internal, loopback only.
- `cli`: carries CLI shared-auth semantics.

Remote pairing always needs approval whatever the id. Plan for the manual `openclaw devices approve` step: the setup-code auto-approve path may apply only to official builds, and I couldn't confirm that in source.

## Risks
- **Protocol drift:** closed schemas reject unknown fields we send, while we decode tolerantly. Keep `ProtocolVersion.pinnedRelease = "2026.9.6"` and add a fixture-refresh script under `Scripts/` that pulls `protocol.schema.json` from npm.
- **Background:** iOS suspends the socket. In v1, `scenePhase` reconnects on foreground and runs catch-up; a run that finishes in the background shows up on return. Push is deferred.
- **ATS:** plain `ws://` to LAN/tailnet needs `NSAllowsLocalNetworking`. Public hosts must use `wss://`.

## Testing & verification strategy
- **Unit** (Swift Testing, `@Test`, parameterized): all in `FancyClawKit`, deterministic via injected clock and `FakeGateway`.
- **Integration**: FakeGateway (in-process NWListener WebSocket) scripted from real doc fixtures.
- **UI**: XCUITest with launch arguments `-FakeGateway` / `-DemoConversation` so UI tests never need a real Gateway.
- **Live (opt-in)**: tests tagged `.live` run against a local `openclaw gateway` on loopback using test token from `.env.example`/scheme env; skipped by default.
- **Agent loop per slice** (XcodeBuildMCP): `session_show_defaults` → `build_sim` → `test_sim` → `build_run_sim` → `snapshot_ui` / `screenshot` to visually verify → fix → commit.
- **End-to-end manual check** (after Slice 6): run `openclaw qr` on the Gateway host, scan in simulator/device, approve with `openclaw devices approve`, chat, kill network, verify reconnect + catch-up.
