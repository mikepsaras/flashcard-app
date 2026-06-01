import Foundation

/// Builds the generation prompt and parses model output into `GeneratedCard`s.
/// The parser is tolerant of markdown fences and surrounding prose.
enum CardJSON {

    // MARK: Prompt

    /// `count == nil` lets the model choose how many cards to create ("auto").
    static func system(count: Int?) -> String {
        let instruction = count.map { "Produce exactly \($0) flashcards." }
            ?? "Produce as many flashcards as the material warrants (typically 8–20)."
        return """
        You are a flashcard generator. \(instruction) From the user's notes or topic, \
        create high-quality study cards. Respond with ONLY a JSON object of the form \
        {"cards":[{"term":"...","definition":"..."}]}. Each "term" is a concise prompt \
        (a word, concept, or question); each "definition" is a clear, accurate answer. \
        Do not include markdown, code fences, or commentary.
        """
    }

    static func user(_ prompt: String, count: Int?) -> String {
        let amount = count.map { "\($0)" } ?? "an appropriate number of"
        return """
        Create \(amount) flashcards from the following. If it is a topic, cover the most \
        important points; if it is notes, extract the key facts.

        \(prompt)
        """
    }

    static func combined(_ prompt: String, count: Int?) -> String {
        system(count: count) + "\n\n" + user(prompt, count: count)
    }

    // MARK: Parse

    private struct CardList: Decodable {
        let cards: [Item]
        struct Item: Decodable { let term: String; let definition: String }
    }

    static func parseCards(from text: String) throws -> [GeneratedCard] {
        let cleaned = stripFences(text)

        // Try each balanced { … } as a {"cards":[ … ]} envelope. Scanning every
        // top-level object (not just first-brace-to-last-brace) means stray prose
        // braces like "I'll make {3} cards: { …json… }" no longer break parsing.
        for object in balancedSpans(in: cleaned, open: "{", close: "}") {
            if let data = object.data(using: .utf8),
               let list = try? JSONDecoder().decode(CardList.self, from: data) {
                return mapped(list.cards)
            }
        }
        // Fallback: a bare top-level array [ {term,definition}, … ] (some providers,
        // e.g. Anthropic with no JSON mode, may answer without the "cards" wrapper).
        for array in balancedSpans(in: cleaned, open: "[", close: "]") {
            if let data = array.data(using: .utf8),
               let items = try? JSONDecoder().decode([CardList.Item].self, from: data) {
                return mapped(items)
            }
        }
        throw AIError.decoding
    }

    private static func mapped(_ items: [CardList.Item]) -> [GeneratedCard] {
        items
            .map {
                GeneratedCard(
                    term: $0.term.trimmingCharacters(in: .whitespacesAndNewlines),
                    definition: $0.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.term.isEmpty }
    }

    /// Removes a surrounding ```json … ``` fence if present.
    static func stripFences(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        let parts = t.components(separatedBy: "```")
        // ["", "json\n<content>", ""] (or ["", "<content>", ""]). Take the body and
        // drop a leading language tag like "json".
        guard parts.count >= 2 else { return t }
        var body = parts[1]
        if let newline = body.firstIndex(of: "\n") {
            let firstLine = body[..<newline].trimmingCharacters(in: .whitespaces).lowercased()
            if firstLine == "json" || firstLine.isEmpty {
                body = String(body[body.index(after: newline)...])
            }
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All top-level balanced `open … close` substrings, in order. String-literal and
    /// escape aware, so braces/brackets inside JSON string values aren't miscounted.
    static func balancedSpans(in text: String, open: Character, close: Character) -> [String] {
        let chars = Array(text)
        var spans: [String] = []
        var i = 0
        while i < chars.count {
            guard chars[i] == open else { i += 1; continue }
            var depth = 0
            var inString = false
            var escaped = false
            var j = i
            var closed = false
            while j < chars.count {
                let c = chars[j]
                if inString {
                    if escaped { escaped = false }
                    else if c == "\\" { escaped = true }
                    else if c == "\"" { inString = false }
                } else if c == "\"" {
                    inString = true
                } else if c == open {
                    depth += 1
                } else if c == close {
                    depth -= 1
                    if depth == 0 { closed = true; break }
                }
                j += 1
            }
            if closed {
                spans.append(String(chars[i...j]))
                i = j + 1
            } else {
                i += 1
            }
        }
        return spans
    }
}
