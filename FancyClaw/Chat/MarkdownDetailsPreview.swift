import DesignSystem
import SwiftUI

private let detailsPreviewSource = """
Before the collapsible section.

<details><summary>Collapsible Section</summary>Hidden content with **markdown**</details>

<details open>
<summary>**Expanded section** with Markdown</summary>

- Textual still renders **bold**, _italics_, and `inline code`.
- [Links](https://example.com) keep the usual behavior.

```swift
let answer = 42
```

<details><summary>Nested section</summary>This stays hidden until expanded.</details>

</details>

After the collapsible sections.
"""

#Preview("Details — light") {
    ScrollView {
        MarkdownText(detailsPreviewSource)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .preferredColorScheme(.light)
}

#Preview("Details — dark XXL") {
    ScrollView {
        MarkdownText(detailsPreviewSource)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.xxLarge)
}
