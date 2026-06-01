import Foundation

/// Builds the generation prompt and parses model output into `GeneratedCard`s.
/// The parser is tolerant of markdown fences and surrounding prose.
enum CardJSON {

    // MARK: Prompt

    static func system(count: Int) -> String {
        """
        You are a flashcard generator. From the user's notes or topic, produce \(count) \
        high-quality study flashcards. Respond with ONLY a JSON object of the form \
        {"cards":[{"term":"...","definition":"..."}]}. Each "term" is a concise prompt \
        (a word, concept, or question); each "definition" is a clear, accurate answer. \
        Do not include markdown, code fences, or commentary.
        """
    }

    static func user(_ prompt: String, count: Int) -> String {
        """
        Create \(count) flashcards from the following. If it is a topic, cover the most \
        important points; if it is notes, extract the key facts.

        \(prompt)
        """
    }

    static func combined(_ prompt: String, count: Int) -> String {
        system(count: count) + "\n\n" + user(prompt, count: count)
    }

    // MARK: Parse

    private struct CardList: Decodable {
        let cards: [Item]
        struct Item: Decodable { let term: String; let definition: String }
    }

    static func parseCards(from text: String) throws -> [GeneratedCard] {
        guard let json = firstJSONObject(in: stripFences(text)),
              let data = json.data(using: .utf8)
        else { throw AIError.decoding }

        guard let list = try? JSONDecoder().decode(CardList.self, from: data) else {
            throw AIError.decoding
        }
        return list.cards
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
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        t = t.replacingOccurrences(of: "```json", with: "```")
            .replacingOccurrences(of: "```JSON", with: "```")
        let parts = t.components(separatedBy: "```")
        // ["", "<content>", ""] for a well-formed fence
        return parts.count >= 2 ? parts[1] : t
    }

    /// Extracts the outermost `{ … }` so leading/trailing prose is ignored.
    static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else { return nil }
        return String(text[start...end])
    }
}
