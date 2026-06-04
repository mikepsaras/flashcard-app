import Testing
import Foundation
@testable import Flashcards

@Suite struct MarkdownTests {
    /// The rendered text drops the inline markers (the styling rides as attributes instead).
    @Test func stripsBoldMarkers() {
        #expect(String(Markdown.attributed("**bold**").characters) == "bold")
    }

    @Test func stripsItalicMarkers() {
        #expect(String(Markdown.attributed("*italic*").characters) == "italic")
    }

    @Test func preservesPlainText() {
        #expect(String(Markdown.attributed("just text").characters) == "just text")
    }

    /// `.inlineOnlyPreservingWhitespace` keeps the author's line breaks (multi-line definitions).
    @Test func preservesLineBreaks() {
        #expect(String(Markdown.attributed("line one\nline two").characters).contains("\n"))
    }

    // MARK: Block parsing (bullet lists)

    @Test func parsesAsteriskBullets() {
        let blocks = Markdown.blocks("* one\n* two")
        #expect(blocks.count == 2)
        #expect(blocks.allSatisfy { $0.isListItem })
        #expect(blocks[0].content == "one")
        #expect(blocks[0].marker == "•")
    }

    @Test func parsesDashAndPlusBullets() {
        #expect(Markdown.blocks("- a").first?.isListItem == true)
        #expect(Markdown.blocks("+ b").first?.isListItem == true)
    }

    /// `*italic*` is inline emphasis, not a list marker (no whitespace after the `*`).
    @Test func inlineEmphasisIsNotABullet() {
        #expect(Markdown.blocks("*italic*").first?.isListItem == false)
        #expect(Markdown.blocks("**bold**").first?.isListItem == false)
        #expect(Markdown.blocks("-5 degrees").first?.isListItem == false)
    }

    @Test func plainLinesAreParagraphs() {
        #expect(Markdown.blocks("hello\nworld").allSatisfy { !$0.isListItem })
    }

    @Test func mixesParagraphsAndBullets() {
        let blocks = Markdown.blocks("Steps:\n* first\n* second")
        #expect(blocks.count == 3)
        #expect(blocks[0].isListItem == false)
        #expect(blocks[1].isListItem && blocks[2].isListItem)
    }

    /// The one-line preview normalizes a leading bullet marker to "•".
    @Test func previewLineNormalizesBullet() {
        #expect(String(Markdown.previewLine("* Identify the problem").characters) == "• Identify the problem")
        #expect(String(Markdown.previewLine("plain text").characters) == "plain text")
    }
}
