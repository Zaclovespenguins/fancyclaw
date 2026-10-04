# Demo approval launch stayed on onboarding

Date: 2026-10-04. Status: observed once; unchanged focused rerun passed, monitor for recurrence.

## Summary

The R4 full test plan failed `ApprovalTests/testApproveAndOtherSessionBadge()` at its first wait for `approval.allow-once.demo-approval`. Launch arguments were `-DemoApprovals`. The failure hierarchy showed the normal onboarding welcome screen after 25 seconds rather than the seeded chat. No approval decision was attempted. All other 318 unique tests passed, including later approval demo coverage. The source is unchanged since that run. The same test passed 1/1 on 2026-10-04, including approval, other-session badge, denial and badge removal. Rerun summary: `/var/folders/4r/lxh0pnjd5tgft5wt0vp4z8dh0000gn/T/ActionArtifacts/default/RunSomeTests/F888C400-E31D-4330-974D-71ABC090B8E1.txt`. No fix has been established or applied.

Observed bundle: `/Volumes/SSDCache/Xcode/DerivedData/FancyClaw-bypnjtyvdvflnmctxqlpgdlhnibo/Logs/Test/Test-FancyClaw-2026.10.03_16-25-43--0600.xcresult`. Exported hierarchy: `/private/tmp/fancyclaw-r4-approval-failure/2D774F05-C3F4-4E48-AD34-49E017D0F522.txt`. Cause is unknown; a transient launch/initialization problem is a possibility, not an established diagnosis.

## Suggested triage

Rerun the unchanged functional test with the official Xcode MCP server. If it repeats, inspect `AppModel.prepareOnce()` and the FakeGateway setup/handshake with launch-session logs and debugger evidence, distinguishing a demo startup failure from approval rendering or permissions. Retain its decision and other-session assertions. Check subsequent full plans for recurrence.

## Actual fix
