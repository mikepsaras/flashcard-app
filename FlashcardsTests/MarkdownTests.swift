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
}
