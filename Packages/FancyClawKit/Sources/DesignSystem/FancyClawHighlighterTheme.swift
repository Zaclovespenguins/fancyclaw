import SwiftUI
import Textual

/// Syntax colors share the app's contrast-tested tokens instead of Textual's unrelated default palette.
extension AppTheme {
    var highlighterTheme: StructuredText.HighlighterTheme {
        StructuredText.HighlighterTheme(
            foregroundColor: textPrimary.dynamicColor,
            backgroundColor: bg.dynamicColor,
            tokenProperties: [
                .keyword: AnyTextProperty(.foregroundColor(accentText.dynamicColor), .fontWeight(.semibold)),
                .literal: AnyTextProperty(.foregroundColor(accentText.dynamicColor)),
                .boolean: AnyTextProperty(.foregroundColor(accentText.dynamicColor)),
                .builtin: AnyTextProperty(.foregroundColor(accentText.dynamicColor)),
                .attribute: AnyTextProperty(.foregroundColor(accentText.dynamicColor)),
                .attributeName: AnyTextProperty(.foregroundColor(accentText.dynamicColor)),
                .preprocessor: AnyTextProperty(.foregroundColor(accentText.dynamicColor)),
                .directive: AnyTextProperty(.foregroundColor(accentText.dynamicColor)),
                .string: AnyTextProperty(.foregroundColor(danger.dynamicColor)),
                .char: AnyTextProperty(.foregroundColor(danger.dynamicColor)),
                .regex: AnyTextProperty(.foregroundColor(danger.dynamicColor)),
                .url: AnyTextProperty(.foregroundColor(accentText.dynamicColor)),
                .comment: AnyTextProperty(.foregroundColor(textSecondary.dynamicColor)),
                .blockComment: AnyTextProperty(.foregroundColor(textSecondary.dynamicColor)),
                .docComment: AnyTextProperty(.foregroundColor(textSecondary.dynamicColor)),
                .inserted: AnyTextProperty(.foregroundColor(diffAdd.dynamicColor)),
                .deleted: AnyTextProperty(.foregroundColor(diffRemove.dynamicColor)),
            ]
        )
    }
}

private extension ThemeColor {
    var dynamicColor: DynamicColor {
        DynamicColor(light: Color(red: light.red, green: light.green, blue: light.blue, opacity: light.opacity),
                     dark: Color(red: dark.red, green: dark.green, blue: dark.blue, opacity: dark.opacity))
    }
}
