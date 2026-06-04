import SwiftUI

/// Lightweight Markdown rendering for card text. `attributed(_:)` handles inline styling (bold,
/// italic, code, links) while preserving the author's line breaks. `blocks(_:)` additionally splits
/// the text into paragraphs and **unordered list items** (`*`, `-`, `+`) so `MarkdownText` can lay a
/// bulleted list out vertically — something a single `Text` can't do. Card text stays plain text on
/// disk; this only affects display, so the `.cards` file format is unchanged.
enum Markdown {
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// One rendered line: a paragraph, or a bullet list item (`marker` is the glyph to show, "•").
    struct Block {
        let content: String
        let marker: String?
        var isListItem: Bool { marker != nil }
    }

    /// Splits text into per-line blocks, classifying lines that start with an unordered-list marker
    /// (`*`, `-`, or `+` followed by whitespace) as bullet items. A marker NOT followed by whitespace
    /// (e.g. `*italic*`, `-5`) stays a paragraph so inline emphasis still works. Pure + testable.
    static func blocks(_ text: String) -> [Block] {
        text.components(separatedBy: .newlines).map { line in
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if let first = trimmed.first, first == "*" || first == "-" || first == "+" {
                let rest = trimmed.dropFirst()
                if let next = rest.first, next == " " || next == "\t" {
                    return Block(content: String(rest.dropFirst()).trimmingCharacters(in: .whitespaces), marker: "•")
                }
            }
            return Block(content: line, marker: nil)
        }
    }

    /// A single-line preview (for the deck-detail list): the first non-empty line, with a leading
    /// list marker shown as "•" instead of the raw `*`/`-`.
    static func previewLine(_ text: String) -> AttributedString {
        guard let block = blocks(text).first(where: { !$0.content.isEmpty }) else { return AttributedString("") }
        return attributed(block.isListItem ? "• " + block.content : block.content)
    }
}

/// Renders card text with inline Markdown **and** block-level bullet lists. Inherits the ambient
/// `.font`/`.foregroundStyle`, so callers style it like a `Text`. List items hang-indent (wrapped
/// lines align under the text, not the bullet). `centered` centers paragraphs when there's no list
/// — matching the study card's single centered term — but lists always left-align.
struct MarkdownText: View {
    let text: String
    var centered: Bool = false

    var body: some View {
        let blocks = Markdown.blocks(text)
        let centerParagraphs = centered && !blocks.contains(where: \.isListItem)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if let marker = block.marker {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).foregroundStyle(.secondary)
                        Text(Markdown.attributed(block.content))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    // An empty source line renders as a blank spacer line (preserves paragraph breaks).
                    Text(block.content.isEmpty ? AttributedString(" ") : Markdown.attributed(block.content))
                        .frame(maxWidth: .infinity, alignment: centerParagraphs ? .center : .leading)
                        .multilineTextAlignment(centerParagraphs ? .center : .leading)
                }
            }
        }
    }
}
