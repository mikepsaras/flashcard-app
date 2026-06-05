import Foundation

/// Builds the generation prompt and parses model output into `GeneratedCard`s.
/// The parser is tolerant of markdown fences and surrounding prose.
enum CardJSON {

    // MARK: Prompt

    /// How many existing cards to send as context when expanding a deck — enough to steer style
    /// and avoid duplicates without blowing up the request size.
    static let maxContextCards = 60

    /// Accepted key spellings (JSON) and header names (CSV) for a card's two sides and its section,
    /// so a card list from any source or AI imports cleanly. Matched case-insensitively; the FIRST
    /// of each is the canonical name the app writes on export. Shared by the JSON and CSV parsers.
    static let frontKeys = ["term", "front", "question", "q", "prompt", "word"]
    static let backKeys = ["definition", "back", "answer", "a", "def", "meaning", "translation"]
    static let sectionKeys = ["section", "category", "group", "topic"]

    /// `count == nil` lets the model choose how many cards to create ("auto"). `expanding`
    /// switches the instructions to "add new cards that don't duplicate the existing ones".
    static func system(count: Int?, expanding: Bool = false) -> String {
        // Only constrain the count when an exact number is requested; in auto mode say nothing
        // about quantity, so the model decides how many cards to create with no bias.
        let countSentence = count.map { " Produce exactly \($0) flashcards." } ?? ""
        let base = """
        You are an expert flashcard author.\(countSentence) Turn the user's notes or topic into \
        high-quality study cards that build durable recall. Follow these card-design rules:
        • One fact per card (the minimum-information principle) — keep each card atomic; split \
        anything bigger into several cards.
        • Make the front a precise question or cue with a single, unambiguous answer. Avoid vague \
        prompts, and avoid yes/no questions (they're too easy to guess).
        • Keep the answer short — a word, a phrase, or one sentence. If it needs many clauses, the \
        card is doing too much.
        • Don't put a list or enumeration on one card; turn each item (or each pair) into its own card.
        • Be accurate and self-contained — don't refer to "the notes", and don't merely restate the \
        term in its own answer.
        Reply with ONLY a JSON object of the form {"cards":[{"term":"...","definition":"..."}]} — no \
        prose around it, and do NOT wrap the JSON in code fences. Each "term" is the card's front (a \
        word, concept, or question); each "definition" is the back (a clear, accurate answer). For \
        example: {"cards":[{"term":"Which organelle generates most of a cell's ATP?","definition":\
        "The mitochondrion"},{"term":"In what year did the Western Roman Empire fall?","definition":\
        "476 CE"}]}. Inside the term/definition text you MAY use lightweight Markdown (**bold**, \
        *italic*, `code`) and LaTeX math — inline as $…$, a display equation as $$…$$ — wherever it \
        makes a card clearer, such as formulas or code. Use formatting only when it helps; plain text \
        is fine otherwise. Keep the JSON valid — in particular, escape backslashes in any LaTeX so \
        each string stays well-formed.
        """
        guard expanding else { return base }
        return base + " " + """
        The user is EXPANDING an existing deck. Create only NEW cards that complement the ones \
        listed in the message — cover gaps, related subtopics, and deeper detail. Do not duplicate \
        or merely rephrase an existing term, and match the existing cards' style and difficulty.
        """
    }

    static func user(_ prompt: String, count: Int?, existing: [GeneratedCard] = []) -> String {
        // A leading count only when an exact number is requested; empty in auto mode.
        let amount = count.map { "\($0) " } ?? ""
        let notes = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !existing.isEmpty else {
            return """
            Create \(amount)flashcards from the following. If it is a topic, cover the most \
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

        Create \(amount)NEW flashcards that complement them without duplicating any existing term.
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
        /// One card, decoded by hand so any accepted key spelling works case-insensitively
        /// (term/front/question/q/…, definition/back/answer/a/…, section/category/…). Model output
        /// and hand-written JSON rarely agree on the exact key names, so we don't pin them.
        struct Item: Decodable {
            let term: String
            let definition: String
            let section: String?

            private struct AnyKey: CodingKey {
                var stringValue: String
                var intValue: Int?
                init(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { return nil }
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: AnyKey.self)
                // Index the object's keys by lowercased name so the lookup is case-insensitive.
                var byLower: [String: AnyKey] = [:]
                for key in container.allKeys { byLower[key.stringValue.lowercased()] = key }
                func value(_ names: [String]) -> String? {
                    for name in names {
                        if let key = byLower[name],
                           let string = try? container.decode(String.self, forKey: key),
                           !string.isEmpty {
                            return string
                        }
                    }
                    return nil
                }
                term = value(CardJSON.frontKeys) ?? ""
                definition = value(CardJSON.backKeys) ?? ""
                section = value(CardJSON.sectionKeys)
            }
        }
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
                let section = $0.section?.trimmingCharacters(in: .whitespacesAndNewlines)
                return GeneratedCard(
                    term: $0.term.trimmingCharacters(in: .whitespacesAndNewlines),
                    definition: $0.definition.trimmingCharacters(in: .whitespacesAndNewlines),
                    section: (section?.isEmpty ?? true) ? nil : section
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
