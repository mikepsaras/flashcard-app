import Foundation

/// Lightweight inline-Markdown rendering for card text. Parses inline styling (bold, italic, code,
/// links) while preserving the author's line breaks; block elements (lists, headings) render
/// inline. Falls back to the raw string when it isn't valid Markdown. Card text stays plain text on
/// disk — this only affects display, so the `.cards` file format is unchanged.
enum Markdown {
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
