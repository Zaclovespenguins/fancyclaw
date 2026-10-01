# Gateway client connection fixes

Date: 2026-10-01. Status: planned; not yet implemented. Parent review: [code-review-2026-10-01](code-review-2026-10-01.md).

Owned files: `Packages/FancyClawKit/Sources/GatewayClient/**` and `Packages/FancyClawKit/Tests/GatewayClientTests/**`. Use FakeGateway as-is; if a new FakeGateway seam is truly required, keep it additive and minimal.

## Summary

### B4 (lifecycle half) — Background/foreground race settles offline
`ConnectionLifecycle.reconcileAvailability` is an actor method that awaits `connection.disconnect()` and only then calls `setStatus(.offline)`. A `setForeground(true)`/`setReachable(true)` that interleaves during that await still sees `status == .connected` and schedules nothing. The first call then resumes and sets `.offline`. Final state: foreground and reachable are both true, there's no recovery task, and the status is `.offline` until the next scene or network change. (The app half of B4 is in [app-integration-fixes](app-integration-fixes.md).)

### B6 — A stale startup retry overwrites the live socket
In `GatewayConnection.connect`, the `isStartupUnavailable` branch sleeps (`Task.sleep`, not injected timing) and `continue`s without re-checking `attemptGeneration == generation`. The next iteration assigns `socket = task`, replacing a newer, ready connection's socket. The stale attempt later throws `CancellationError` from its generation guard, but doesn't restore the socket. `ready` stays true, and every `request()` sends on a cancelled socket. Calls not wrapped by lifecycle cancellation are exposed (`AppModel` connect/reconnect paths).

### B10 — A Keychain failure after the handshake
`saveDeviceToken` can throw after `ready`, `mediaOrigin`, `mediaBearer` and `policy` are set. The catch closes the authenticated socket and leaves the media origin and bearer populated. A `KeychainError` isn't a `GatewayErrorShape`, so lifecycle recovery retries forever.

### B11 — RPC timeouts and cancellation
`request()` spawns a timeout `Task` per RPC that is never cancelled and holds the actor for the full timeout. The continuation ignores caller cancellation, so a cancelled caller waits up to 15 s.

### B12 — Pairing skips the final attempt
`PairingRetrySchedule.delay` clips the last sleep to the remaining time. On the next loop pass, `PairingCoordinator.connect` sees `remaining <= 0` and throws `lastPairingError` without retrying, so an approval granted in that final window is missed.

## Suggested triage

Write each regression test first and confirm it fails; then fix. Keep the strict-encode and tolerant-decode rules, and inject timing.

- **B4 plan:** In `reconcileAvailability`, set `.offline` (and bump `epoch`) *before* awaiting `disconnect()`. After the await, re-read `foreground && reachable` and call `scheduleRecovery()` if both are now true. Make sure a recovery scheduled during the await is not cancelled by the earlier call.
  **B4 test:**
  - Lifecycle connected to FakeGateway.
  - Run `setForeground(false)` and `setForeground(true)` concurrently in a task group, about 50 iterations; also run a reachability variant.
  - After settling with injected timing, expect `status` to be `.connected` or `.reconnecting`, and never a settled `.offline` while foreground and reachable.
- **B6 plan:**
  - Re-check `attemptGeneration == generation` after the retry sleep (throw `CancellationError` if stale).
  - Assign `socket` only once the attempt is still current, or only after a successful handshake. Never clobber the socket of a newer generation in the catch path either.
  - Route the startup retry sleep through an injected `GatewayTiming`. Add an optional `timing` parameter with the `.continuous` default, so existing callers compile unchanged.
  **B6 test:**
  - FakeGateway answers the first connect with startup-unavailable and `retryAfterMs`.
  - Start connect A; while it sleeps, run disconnect plus connect B to completion.
  - After A finishes (throws cancellation), `request("sessions.list")` on the connection must succeed.
- **B10 plan:** Treat a Keychain save failure as non-fatal. Log it with `os.Logger` (no token values) and keep the connection; the stored token simply isn't refreshed. Also clear `mediaOrigin`/`mediaBearer`/`policy` in the catch path for genuine failures after `ready`.
  **B10 test:** If the identity store isn't already injectable, add a minimal protocol seam. Use a store whose `saveDeviceToken` throws. Expect connect to succeed and a later RPC to work.
- **B11 plan:**
  - Keep a handle to the timeout task and cancel it when the response arrives or fails. For example, store it alongside the pending continuation, or use a task group race.
  - Wrap the continuation in `withTaskCancellationHandler` so caller cancellation fails that pending ID with `CancellationError`.
  - Use injected timing for the timeout if `GatewayConnection` already has it; otherwise keep `Task.sleep` and note the reason.
  **B11 test:**
  - FakeGateway never replies to a method.
  - Cancel the calling task after 100 ms; expect `CancellationError` within 1 s.
  - Separately, verify a normal reply still works and that a timed-out RPC still throws `timedOut`.
- **B12 plan:** After a sleep that ends at the deadline, permit exactly one final attempt. For example, decide on termination *after* an attempt rather than before it, or have the schedule return the clipped delay together with a "last attempt" marker.
  **B12 test:**
  - Fake elapsed clock, `maximumDuration` 5 s, delays `[3s]`.
  - The operation throws pairing-required once, then succeeds.
  - Expect success. Also expect that a still-failing operation throws after exactly the final attempt.

Verify by running `GatewayClientTests` through the simulator test plan, then build the app.

## Actual fix

