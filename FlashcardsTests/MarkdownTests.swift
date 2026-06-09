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

    // MARK: Inline runs (text vs. inline math)

    @Test func splitsInlineMath() {
        #expect(Markdown.inlineRuns("a $x^2$ b") == [.text("a "), .math("x^2"), .text(" b")])
    }

    @Test func plainTextHasNoMath() {
        #expect(Markdown.inlineRuns("just text") == [.text("just text")])
    }

    @Test func escapedDollarIsLiteral() {
        #expect(Markdown.inlineRuns("it costs \\$5 today") == [.text("it costs $5 today")])
    }

    @Test func dollarInCodeSpanIsNotMath() {
        // The backtick span keeps `$5` as literal text, not a math delimiter.
        #expect(Markdown.inlineRuns("use `$5` here") == [.text("use `$5` here")])
    }

    @Test func parsesAccentSpan() {
        // `==text==` becomes an accent run (rendered in the card's accent color).
        #expect(Markdown.inlineRuns("a ==b== c") == [.text("a "), .accent("b"), .text(" c")])
    }

    @Test func accentInCodeSpanIsLiteral() {
        // `==x==` inside a backtick span stays literal text, not an accent run.
        #expect(Markdown.inlineRuns("use `==x==` here") == [.text("use `==x==` here")])
    }

    @Test func unclosedAccentIsLiteral() {
        #expect(Markdown.inlineRuns("a == b") == [.text("a == b")])
    }

    // MARK: Block parsing

    @Test func parsesBulletList() {
        let blocks = Markdown.blocks("- one\n- two")
        #expect(blocks == [.bulletList([.init(blocks: [.paragraph("one")]), .init(blocks: [.paragraph("two")])])])
    }

    @Test func parsesOrderedList() {
        guard case let .orderedList(start, items) = Markdown.blocks("3. a\n4. b").first else {
            Issue.record("expected ordered list"); return
        }
        #expect(start == 3)
        #expect(items.count == 2)
    }

    @Test func parsesHeading() {
        #expect(Markdown.blocks("## Title").first == .heading(level: 2, source: "Title"))
        // No space after #'s → not a heading.
        #expect(Markdown.blocks("##notitle").first == .paragraph("##notitle"))
    }

    @Test func parsesDisplayMath() {
        #expect(Markdown.blocks("$$x^2 + y^2 = z^2$$").first == .displayMath("x^2 + y^2 = z^2"))
    }

    @Test func parsesFencedCode() {
        #expect(Markdown.blocks("```swift\nlet x = 1\n```").first == .code(language: "swift", code: "let x = 1"))
    }

    @Test func parsesBlockquote() {
        #expect(Markdown.blocks("> quoted").first == .quote([.paragraph("quoted")]))
    }

    @Test func nestsLists() {
        // A more-indented bullet under an item becomes a nested list inside that item.
        guard case let .bulletList(items) = Markdown.blocks("- outer\n  - inner").first, let first = items.first else {
            Issue.record("expected bullet list"); return
        }
        #expect(first.blocks.contains { if case .bulletList = $0 { true } else { false } })
    }

    @Test func inlineEmphasisIsNotAList() {
        #expect(Markdown.blocks("*italic*") == [.paragraph("*italic*")])
        #expect(Markdown.blocks("-5 degrees") == [.paragraph("-5 degrees")])
    }

    /// The one-line preview normalizes a leading bullet marker to "•" and strips math delimiters.
    @Test func previewLineNormalizesBullet() {
        #expect(String(Markdown.previewLine("* Identify the problem").characters) == "• Identify the problem")
        #expect(String(Markdown.previewLine("plain text").characters) == "plain text")
        #expect(String(Markdown.previewLine("area is $x^2$").characters) == "area is x^2")
        #expect(String(Markdown.previewLine("==key== fact").characters) == "key fact")
    }
}
