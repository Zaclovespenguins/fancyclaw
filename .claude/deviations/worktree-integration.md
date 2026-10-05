# Worktree integration into main

Date: 2026-10-05. Status: integrated; build verified; full test run stopped at the owner's request.

## Integration

- Audited all six registered checkouts (main and five Claude Code worktrees), every local branch, the Codex worktree directory, and the three internal Codex snapshot trees. No separate Codex checkout exists; each snapshot exactly matches the tracked files of an existing main-history commit (`abea0b6` or `9777e2b`). Snapshot-only files are existing local device tooling/logs and duplicate design reference sources.
- Three Claude Code worktree heads were already ancestors of main: `409014f` (project skeleton/guidance), `935c65a` (protocol models), and `0c4b338` (review fixes).
- Committed the planning checkout's four outstanding documents as `b5728ba` (`docs: preserve dashboard redesign plans and deferred features`), then merged its branch in `1bf1573` (`Merge Claude Code dashboard redesign planning into main`).
- Integrated the nine committed R1–R7 redesign changes through `4a6dadd`, preserving their original descriptive commits. The only conflicts were the deviations index and the two planning documents; their completed redesign versions supersede the original drafts. Retained the planning checkout's per-slice documentation convention in `CLAUDE.md`.
- The integrated app, package, extension, test source, and design references exactly match the completed redesign branch. The later owner-requested default test-plan change is recorded below. `AGENTS.md` remains a symlink to `CLAUDE.md`. All five linked checkouts are clean. Existing untracked design archives, local device script/logs, and checkout directories remain untouched and uncommitted. No remote was added, nothing was pushed, and no branch or worktree was deleted.

## Verification

- Official Xcode MCP app/extension/test-target build succeeded with zero errors using scheme/test plan FancyClaw, Debug, iPhone 18 Pro / iOS 27.0. Build log: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261005-135901.txt`.
- The original full-plan MCP request timed out after 300 seconds while Xcode continued. The owner then asked to disable UI testing because of its duration; the active run was stopped with the official `StopProject` tool. Its finalized partial result reports **276 passed, 18 failed, 0 skipped** (294 results; parameterized device results have 424 passes). This is an incomplete, failing run, not a full-suite pass. Failures comprise 14 ChatCore tests killed by signal, one lost-connection-to-testmanagerd error, the model-menu UI assertion, the Chats screenshot lookup, and the UI test canceled when stopping. Causes were not investigated in this integration task.
- Stopped result bundle: `/Volumes/SSDCache/Xcode/DerivedData/FancyClaw-cuslxoojkxbnodaxyjxcjqyjwuhl/Logs/Test/Test-FancyClaw-2026.10.05_13-59-19--0600.xcresult`. Finalized summary export: `/private/tmp/fancyclaw-worktree-integration-stopped-summary.json`.
- Verified all six checkout heads are ancestors of main and every checkout has clean tracked files; `git branch --no-merged main` is empty. `AGENTS.md` remains a symlink. Whitespace and conflict-index checks passed.

## Default testing policy (owner request, 2026-10-05)

- Excluded `FancyClawUITests` from `FancyClaw.xctestplan`; the seven package test targets remain the default suite. The UI project target and all UI-test source remain intact and must only be restored to the default plan when the owner asks.
- Updated `CLAUDE.md` (and its `AGENTS.md` symlink) so later agents follow this testing preference. No additional UI tests were launched after the request.
- An initial attempt to verify the package-only default through `RunAllTests` was rejected by automatic approval review because Xcode's active test listing still showed UI tests enabled. No test run started. Removed the UI target from the default plan entirely to make its exclusion explicit; verification uses the saved plan structure and shared scheme reference without executing tests. Xcode's cached test catalog continued to list 353 tests, including four old UI tests absent from the current source; this catalog was not treated as evidence that the revised plan had executed. No package-only test pass is claimed, and the owner's active physical-phone session was left running.
