# Redesign R5: Chats

Date: 2026-10-04. Plan: `layout_redesign.md`, Slice R5. Status: implemented, root-reviewed and simulator-verified.

## Implementation

- Chats uses the native large navigation title and always-visible native search drawer above an inset grouped list. The ambient theme background and theme row surfaces support light/dark appearances. Existing Pinned / Today / Yesterday / Earlier groups, search, pagination, pull to refresh, errors, empty states, compose, swipe actions and context-menu mutations remain.
- Rows show the canonical title, relative last-activity time (updated time fallback), a two-line preview, and separate Running / Needs approval chips. Both chips appear when the Gateway roster marks an active run and the live ApprovalStore has pending commands. The selected-session checkmark remains.
- Status labels use primary theme text, with an online green dot/tint or coral command icon/tint. This avoids relying on the decorative green token as small text. Title/time reflow vertically at accessibility sizes; status chips fall back to a vertical stack when needed. No accessibility audits or repair work were added, following the owner's steering.
- `SessionListPresentation` extracts only date grouping/time lookup. It preserves the filtered roster's order within each group, gives pinned rows precedence, uses `lastActivityAt` before `updatedAt`, omits empty groups and places undated sessions in Earlier. Calendar-day comparison handles daylight-saving boundaries without subtracting a fixed 24 hours.
- Existing `sessions.row.*`, `sessions.approvals.*`, `sessions.new`, and `sessions.name` identifiers remain. New identifiers cover the list, group headers, running chips, load-more and empty states. The approval chip replaces the former terminal-count badge while retaining its pending count in the spoken label.
- Dedicated `-DemoSessions` seeds all four groups, nonempty previews, a running chat with a pending command, and an archived row. It starts on Chats using only an ephemeral FakeGateway and in-memory cache. `-DemoSessionsEmpty` seeds an empty roster for first-chat behavior. The Home fixture and semantics are unchanged.

## Choices and limits

- Native search remains `.navigationBarDrawer(displayMode: .always)` so search is directly available beneath the large title. Prior audit-only search clipping findings are deferred under `redesign-accessibility-deferred.md`; removal of audits does not establish they are fixed.
- The list uses native inset grouped section surfaces rather than custom glass per row, retaining native swipes/context menus and a clear date hierarchy. Compose calls the same root action as the detached tab-bar compose button.
- Store mutations, remote search/page routing, cached data boundaries and connection-wide transient approvals are unchanged. No temporary mutation/navigation gating or new dependency was introduced.

## Verification prepared

- `SessionListPresentationTests`: pinned precedence, activity-time fallback/precedence, roster order, missing dates, omitted empty groups, a DST calendar-day boundary, and fixture coverage of all groups plus combined running/approval state.
- `SessionStoreTests`: additional roster/search pagination routing, query preservation and archived filtering regression using scripted FakeGateway responses. Existing create/rename/model/reset/archive-delete and cached search regressions remain.
- `SessionsTests`: existing create/rename/delete flow plus cancellation of deletion; group/status/search/search-empty/query-clear checks; reset cancellation and confirmed history removal; empty roster compose; rejected rename preserves the title and shows a dismissible error; light/dark default/XXL screenshots at the top and Earlier sections (eight retained screenshots across four appearances).
- Existing ApprovalTests still verify the preserved `sessions.approvals.*` chip disappears after resolving the other chat's command. Existing PolishTests retain functional navigation and screenshots without audits.
- Implementation agent did not invoke Xcode builds/tests, contact a live Gateway, or commit. Root will record build, focused/full test counts, logs and visual review below.

## Root review and verification

- Full-plan Settings verification exposed an onboarding page-selection mismatch after disconnect; narrow initialization correction and pending verification are recorded in `debugging/onboarding-page-selection.md`. The Settings test still requires leaving the tab shell and reaching the actual connection form.

- Root reviewed the list, row/chip views, grouping helper, dedicated demo modes and all new/updated tests. Corrections included a shadowed grouping function name, native search Close/Cancel lookup, waiting for asynchronous reset history removal, and requiring the request count before indexing pagination assertions. A temporary navigation gate proposed during test preparation was removed to preserve existing mutation/navigation behavior.
- Official FancyClaw / Debug / iPhone 18 Pro / iOS 27.0 app, extension and test-target build succeeded with **zero errors**. Log: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261004-174347.txt`.
- Focused tests are running: the three grouping tests, pagination regression, six Sessions UI tests, existing other-session approval-chip test, Home search-isolation test, and two retained Polish navigation tests. Screenshot/full-plan outcomes will be recorded after completion.


- First focused run: **14 tests: 12 passed, 2 failed, 0 skipped**. All four package tests passed. Existing approval-chip, Home search-isolation and Polish navigation tests passed. Both failures were new cancellation checks expecting a visible Cancel button in iOS 27's native confirmation popover, which instead exposes a `PopoverDismissRegion`. Cancellation coverage is being corrected to exercise native dismissal while retaining unchanged-chat/history assertions. Bundle: `/Volumes/SSDCache/Xcode/DerivedData/FancyClaw-bypnjtyvdvflnmctxqlpgdlhnibo/Logs/Test/Test-FancyClaw-2026.10.04_17-44-06--0600.xcresult`.
- Root reviewed all **eight Chats screenshots** (top and Earlier sections in light/dark, default/XXL). Date hierarchy, titles, two-line previews, relative times and both status chips have the intended layout; scrolling exposes the lower groups with the native minimizing tab bar. Contact sheet: `/private/tmp/fancyclaw-r5-screens/matrix.jpg`.

- Corrected native cancellation tests passed **2/2**, retaining cancellation preservation and subsequent confirmed delete/reset behavior. Summary: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/RunSomeTests/FA5C7EF2-C9BA-4F43-9D28-190A09C1E0B9.txt`. Build after the only test-source change succeeded with **zero errors**: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261004-175358.txt`. Full plan is the remaining verification gate.

- Full plan finalized: **328 unique tests: 327 passed, 1 failed, 0 skipped**; expanded parameterized count **473: 472 passed, 1 failed**. All **296 package declarations** passed: GatewayProtocol 75, GatewayClient 36, ChatCore 121, Persistence 4, DesignSystem 14, TestSupport 12, SystemIntegration 34. UI **31 passed, 1 failed**. All six Sessions tests passed, including corrected cancellation. The R4 initial approval-demo launch failure did not recur.
- The sole full-plan failure was `SettingsTests/testReconnectAndDisconnect()` expecting the connection form immediately after disconnect. Captured hierarchy confirms the app successfully returned to the onboarding welcome page (`FancyClaw` navigation title, “Set up connection” button, no tab bar). The test is being corrected to follow the public welcome-to-form path when needed, retaining disconnection and setup assertions. Bundle: `/Volumes/SSDCache/Xcode/DerivedData/FancyClaw-bypnjtyvdvflnmctxqlpgdlhnibo/Logs/Test/Test-FancyClaw-2026.10.04_17-57-06--0600.xcresult`; exported hierarchy: `/private/tmp/fancyclaw-r5-settings-failure/4FE736F8-91DE-4130-A30B-45741262915C.txt`.

- Final correction verification: initializing onboarding from its supplied profile before the first native pager render fixed the repeated page/content mismatch. Official build succeeded with **zero errors**: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261004-183111.txt`. Focused Settings reconnect/disconnect, initial FakeGateway form/send, normal welcome error recovery and large-text onboarding all passed **4/4**. Summary: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/RunSomeTests/8F59AEF6-17F6-4B98-B779-1E0890FEAFCC.txt`. The original full-run result remains 327/328; its one failed case and the related onboarding regressions now have passing focused evidence. The next slice full plan will exercise the correction again.
