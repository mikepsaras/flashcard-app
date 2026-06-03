import Foundation

/// Builds the generation prompt and parses model output into `GeneratedCard`s.
/// The parser is tolerant of markdown fences and surrounding prose.
enum CardJSON {

    // MARK: Prompt

    /// How many existing cards to send as context when expanding a deck — enough to steer style
    /// and avoid duplicates without blowing up the request size.
    static let maxContextCards = 60

    /// `count == nil` lets the model choose how many cards to create ("auto"). `expanding`
    /// switches the instructions to "add new cards that don't duplicate the existing ones".
    static func system(count: Int?, expanding: Bool = false) -> String {
        let instruction = count.map { "Produce exactly \($0) flashcards." }
            ?? "Produce as many flashcards as the material warrants."
        let base = """
        You are a flashcard generator. \(instruction) From the user's notes or topic, \
        create high-quality study cards. Respond with ONLY a JSON object of the form \
        {"cards":[{"term":"...","definition":"..."}]}. Each "term" is a concise prompt \
        (a word, concept, or question); each "definition" is a clear, accurate answer. \
        Do not include markdown, code fences, or commentary.
        """
        guard expanding else { return base }
        return base + " " + """
        The user is EXPANDING an existing deck. Create only NEW cards that complement the ones \
        listed in the message — cover gaps, related subtopics, and deeper detail. Do not duplicate \
        or merely rephrase an existing term, and match the existing cards' style and difficulty.
        """
    }

    static func user(_ prompt: String, count: Int?, existing: [GeneratedCard] = []) -> String {
        let amount = count.map { "\($0)" } ?? "an appropriate number of"
        let notes = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !existing.isEmpty else {
            return """
            Create \(amount) flashcards from the following. If it is a topic, cover the most \
            important points; if it is notes, extract the key facts.

            \(notes)
            """
        }

        // Expanding: send the current cards so the model avoids duplicates and matches style.
        let list = existing.prefix(maxContextCards)
            .map { "- \($0.term): \($0.definition)" }
            .joined(separator: "\n")
        var out = """
        The deck already contains these flashcards:

        \(list)

        Create \(amount) NEW flashcards that complement them without duplicating any existing term.
        """
        if !notes.isEmpty {
            out += "\n\nFocus on or draw from the following notes/topic:\n\n\(notes)"
        }
        return out
    }

    static func combined(_ prompt: String, count: Int?, existing: [GeneratedCard] = []) -> String {
        system(count: count, expanding: !existing.isEmpty) + "\n\n" + user(prompt, count: count, existing: existing)
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
