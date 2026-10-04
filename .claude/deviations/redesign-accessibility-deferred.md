# Accessibility checks deferred

Date: 2026-10-03. Status: owner-directed change implemented and functionally verified with R4.

The owner asked to deprioritize accessibility ("Let’s not be super worried about accessibility right now") and remove tests for purely accessibility-related findings. Polish UI tests now retain functional assertions, navigation and appearance screenshots, while their `performAccessibilityAudit` calls and audit-only helper are removed. Names reflect the remaining behavioral checks. No functional failure assertion is weakened.

Nested custom `.combine` caption elements were removed from attachment/file metadata; native text children, button labels and test identifiers remain. The Settings explanation returns to ordinary semantic SwiftUI text, removing the UIKit bridge added only to satisfy the Dynamic Type audit. Its explanation and four-variant screenshots remain.

Unresolved audit findings are listed in `Future_features.md`. Earlier test reports remain historical evidence, not claims that those findings have been corrected. This supersedes the plan's audit-passing gate and the R3 native-label choice. Builds, functional tests and layout screenshots remain required.

R4 verification retained all five Polish tests and both link-preview UI tests; all passed in the full plan. All eight Home appearance screenshots were reviewed. The full plan ran 319 unique tests with 318 passes and one unrelated demo-startup failure, which passed on unchanged focused rerun. Full counts and evidence paths are in `redesign-r4-home.md`. These results establish functional coverage after removing audit calls; they do not certify accessibility.
