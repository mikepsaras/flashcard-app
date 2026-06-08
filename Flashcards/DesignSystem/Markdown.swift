import SwiftUI
import SwiftMath

/// Markdown + LaTeX rendering for card text. `attributed(_:)` handles inline styling (bold, italic,
/// code, links); `blocks(_:)` parses block structure (headings, lists, blockquotes, fenced code,
/// rules, display math); `MarkdownText` renders it, interleaving inline `$…$` and display `$$…$$`
/// math. Card text stays plain text on disk — this only affects display, so the `.cards` format is
/// unchanged. Tables are not yet supported (rendered as plain paragraphs).
enum Markdown {
    /// Inline-only AttributedString (bold/italic/code/links), preserving line breaks. Used for the
    /// non-math runs of a paragraph and for one-line row previews.
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// First non-empty line for a one-line preview, with a leading bullet, quote, or heading marker
    /// shown as "•" (ordered "1." markers are left as-is) and math delimiters stripped so a row never
    /// shows a raw `$…$`.
    static func previewLine(_ text: String) -> AttributedString {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var stripped = line
        for marker in ["- ", "* ", "+ ", "> ", "# "] where stripped.hasPrefix(marker) {
            stripped = "• " + stripped.dropFirst(marker.count); break
        }
        stripped = stripped.replacingOccurrences(of: "$", with: "")
        return attributed(stripped)
    }

    // MARK: Block model

    struct Item: Equatable { var blocks: [Block] }

    indirect enum Block: Equatable {
        case heading(level: Int, source: String)
        case paragraph(String)
        case bulletList([Item])
        case orderedList(start: Int, items: [Item])
        case quote([Block])
        case code(language: String?, code: String)
        case rule
        case displayMath(String)

        /// Paragraph-like blocks can be center-aligned on the study card; structural blocks left-align.
        var isSimple: Bool {
            switch self {
            case .paragraph, .heading, .displayMath: true
            default: false
            }
        }
    }

    // MARK: Inline runs (text vs. inline math)

    enum InlineRun: Equatable { case text(String); case math(String) }

    /// Splits a line into text and inline-`$…$`-math runs. `\$` is a literal dollar; `$` inside a
    /// backtick code span is left as text (not math).
    static func inlineRuns(_ s: String) -> [InlineRun] {
        var runs: [InlineRun] = []
        var text = ""
        let chars = Array(s)
        var i = 0
        var inCode = false
        func flush() { if !text.isEmpty { runs.append(.text(text)); text = "" } }
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "$" { text.append("$"); i += 2; continue }
            if c == "`" { inCode.toggle(); text.append(c); i += 1; continue }
            if c == "$", !inCode {
                var j = i + 1
                var math = ""
                var closed = false
                while j < chars.count {
                    if chars[j] == "\\", j + 1 < chars.count, chars[j + 1] == "$" { math.append("$"); j += 2; continue }
                    if chars[j] == "`" { break }
                    if chars[j] == "$" { closed = true; break }
                    math.append(chars[j]); j += 1
                }
                if closed, !math.trimmingCharacters(in: .whitespaces).isEmpty {
                    flush(); runs.append(.math(math)); i = j + 1; continue
                }
            }
            text.append(c); i += 1
        }
        flush()
        return runs
    }

    // MARK: Block parser

    static func blocks(_ text: String) -> [Block] {
        parse(text.components(separatedBy: "\n"))
    }

    private static func parse(_ lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.isEmpty { i += 1; continue }

            // Fenced code ```lang ... ```
            if t.hasPrefix("```") {
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }   // closing fence
                blocks.append(.code(language: lang.isEmpty ? nil : lang, code: code.joined(separator: "\n")))
                continue
            }

            // Display math $$ … $$  (single-line or fenced across lines)
            if t.hasPrefix("$$") {
                if t.count >= 4, t.hasSuffix("$$") {
                    blocks.append(.displayMath(String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)))
                    i += 1; continue
                }
                var math = [String(t.dropFirst(2))]
                i += 1
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasSuffix("$$") { math.append(String(l.dropLast(2))); i += 1; break }
                    math.append(lines[i]); i += 1
                }
                blocks.append(.displayMath(math.joined(separator: " ").trimmingCharacters(in: .whitespaces)))
                continue
            }

            // Heading
            if let heading = parseHeading(t) { blocks.append(heading); i += 1; continue }

            // Thematic break
            if isRule(t) { blocks.append(.rule); i += 1; continue }

            // Blockquote — gather consecutive `>` lines, strip one level, recurse.
            if t.hasPrefix(">") {
                var inner: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces)
                    l.removeFirst()
                    if l.hasPrefix(" ") { l.removeFirst() }
                    inner.append(l); i += 1
                }
                blocks.append(.quote(parse(inner)))
                continue
            }

            // Lists
            if listMarker(line) != nil {
                let (list, next) = parseList(lines, from: i)
                blocks.append(list); i = next; continue
            }

            // Paragraph — consecutive lines until a blank or a new block starts.
            var para = [line]
            i += 1
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmingCharacters(in: .whitespaces)
                if lt.isEmpty || lt.hasPrefix("```") || lt.hasPrefix("$$") || lt.hasPrefix(">")
                    || parseHeading(lt) != nil || isRule(lt) || listMarker(l) != nil { break }
                para.append(l); i += 1
            }
            blocks.append(.paragraph(para.joined(separator: "\n")))
        }
        return blocks
    }

    /// Parses one list (all items at the starting indent), returning the block and the next line index.
    /// Lines indented past an item's marker belong to that item and are parsed recursively (nesting).
    private static func parseList(_ lines: [String], from start: Int) -> (Block, Int) {
        guard let first = listMarker(lines[start]) else { return (.paragraph(lines[start]), start + 1) }
        let indent = first.indent
        let ordered = first.ordered
        var items: [Item] = []
        var i = start
        while i < lines.count {
            guard let marker = listMarker(lines[i]), marker.indent == indent, marker.ordered == ordered else {
                if lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
                break
            }
            var itemLines = [marker.content]
            i += 1
            // Continuation / nested lines: more indented than this marker's content column, or blanks.
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmingCharacters(in: .whitespaces)
                if lt.isEmpty { i += 1; continue }
                if leadingSpaces(l) >= marker.contentColumn {
                    itemLines.append(String(l.dropFirst(marker.contentColumn)))
                    i += 1
                } else { break }
            }
            items.append(Item(blocks: parse(itemLines)))
        }
        return (ordered ? .orderedList(start: first.number, items: items) : .bulletList(items), i)
    }

    // MARK: Line helpers

    private static func parseHeading(_ t: String) -> Block? {
        var level = 0
        for c in t { if c == "#" { level += 1 } else { break } }
        guard (1...6).contains(level), level < t.count else { return nil }
        let rest = t.dropFirst(level)
        guard rest.first == " " else { return nil }
        return .heading(level: level, source: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ t: String) -> Bool {
        let chars = Set(t.filter { !$0.isWhitespace })
        return t.filter({ !$0.isWhitespace }).count >= 3 && (chars == ["-"] || chars == ["*"] || chars == ["_"])
    }

    private static func leadingSpaces(_ s: String) -> Int { s.prefix { $0 == " " }.count }

    struct Marker { let ordered: Bool; let number: Int; let indent: Int; let contentColumn: Int; let content: String }

    /// Recognizes `- `/`* `/`+ ` (unordered) and `1. `/`1) ` (ordered) list markers.
    private static func listMarker(_ line: String) -> Marker? {
        let indent = leadingSpaces(line)
        let rest = Array(line.dropFirst(indent))
        guard let first = rest.first else { return nil }
        if first == "-" || first == "*" || first == "+", rest.count >= 2, rest[1] == " " {
            let content = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return Marker(ordered: false, number: 1, indent: indent, contentColumn: indent + 2, content: content)
        }
        // ordered: digits then . or )
        var k = 0
        while k < rest.count, rest[k].isNumber { k += 1 }
        if k > 0, k + 1 < rest.count, rest[k] == "." || rest[k] == ")", rest[k + 1] == " " {
            let number = Int(String(rest[0..<k])) ?? 1
            let content = String(rest.dropFirst(k + 2)).trimmingCharacters(in: .whitespaces)
            return Marker(ordered: true, number: number, indent: indent, contentColumn: indent + k + 2, content: content)
        }
        return nil
    }
}

// MARK: Renderer

/// Renders card text with full markdown + LaTeX. Inherits no font — pass `baseSize` (point size) so
/// math can be sized to match. `centered` centers paragraph-only content (the study card's term);
/// any structural block (list/quote/code) left-aligns everything.
struct MarkdownText: View {
    let text: String
    var baseSize: CGFloat = 17
    var weight: Font.Weight = .regular
    var centered: Bool = false
    var mathColor: MTColor = MathColor.label

    var body: some View {
        let blocks = Markdown.blocks(text)
        let centerAll = centered && blocks.allSatisfy(\.isSimple)
        blockList(blocks, centerAll: centerAll)
    }

    @ViewBuilder private func blockList(_ blocks: [Markdown.Block], centerAll: Bool) -> some View {
        VStack(alignment: centerAll ? .center : .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block, centerAll: centerAll)
            }
        }
    }

    // Type-erased to break the block → list/quote → block recursion (opaque types can't self-refer).
    private func blockView(_ block: Markdown.Block, centerAll: Bool) -> AnyView {
        AnyView(blockBody(block, centerAll: centerAll))
    }

    @ViewBuilder private func blockBody(_ block: Markdown.Block, centerAll: Bool) -> some View {
        switch block {
        case let .heading(level, source):
            inlineText(source, size: headingSize(level), weight: .bold)
                .frame(maxWidth: .infinity, alignment: centerAll ? .center : .leading)
                .multilineTextAlignment(centerAll ? .center : .leading)

        case let .paragraph(source):
            inlineText(source, size: baseSize, weight: weight)
                .frame(maxWidth: .infinity, alignment: centerAll ? .center : .leading)
                .multilineTextAlignment(centerAll ? .center : .leading)

        case let .bulletList(items):
            listView(items, marker: { _ in "•" })

        case let .orderedList(start, items):
            listView(items, marker: { "\(start + $0)." })

        case let .quote(blocks):
            // Bar as a leading overlay (not an HStack with a greedy Rectangle, which would stretch to
            // absorb any slack vertical space); the overlay sizes the bar to the content's height.
            blockList(blocks, centerAll: false)
                .foregroundStyle(.secondary)
                .padding(.leading, 13)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(.secondary.opacity(0.5)).frame(width: 3)
                }

        case let .code(_, code):
            Text(code)
                .font(.system(size: baseSize * 0.88, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .rule:
            Divider().padding(.vertical, 2)

        case let .displayMath(latex):
            MathDisplayView(latex: latex, fontSize: baseSize * 1.15, color: mathColor)
                .frame(maxWidth: .infinity, alignment: centerAll ? .center : .leading)
        }
    }

    @ViewBuilder private func listView(_ items: [Markdown.Item], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker(index))
                        .font(.system(size: baseSize, weight: weight, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    blockList(item.blocks, centerAll: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Builds one flowing `Text` from a line's inline runs: styled text via AttributedString, inline
    /// math via baseline-aligned images.
    private func inlineText(_ source: String, size: CGFloat, weight: Font.Weight) -> Text {
        var result = Text("")
        for run in Markdown.inlineRuns(source) {
            switch run {
            case let .text(t):
                result = result + Text(Markdown.attributed(t))
            case let .math(m):
                result = result + inlineMathText(m, fontSize: size, color: mathColor)
            }
        }
        return result.font(.system(size: size, weight: weight, design: .rounded))
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: baseSize * 1.55
        case 2: baseSize * 1.35
        case 3: baseSize * 1.2
        case 4: baseSize * 1.1
        default: baseSize
        }
    }
}
