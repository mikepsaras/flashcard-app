import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Parses loose card lists — pasted text or imported files — into cards, sniffing the format
/// (JSON or CSV) rather than committing to one. JSON is read with the same tolerant parser the
/// AI generator uses (markdown fences, surrounding prose, a `{"cards":…}` envelope, or a bare
/// array); an optional top-level `name`/`section`/`description` is captured so a JSON file can
/// seed a whole new deck. Also encodes a deck's cards back out as JSON.
enum CardListCodec {
    /// A parsed card list, plus optional deck metadata when the source carried it.
    struct Parsed: Equatable {
        var name: String?
        var section: String?
        var deckDescription: String?
        var cards: [GeneratedCard]
        var isEmpty: Bool { cards.isEmpty }
    }

    // MARK: Parse

    /// Parses `text` into cards. Tries JSON first (the tolerant reader returns nothing on
    /// non-JSON), then CSV — so the caller doesn't need to know or declare the format.
    static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Parsed(cards: []) }

        let json = parseJSON(trimmed)
        if let json, !json.cards.isEmpty { return json }

        let csv = parseCSV(trimmed)
        if !csv.isEmpty { return Parsed(cards: csv) }

        // Neither produced cards; surface a name-only JSON envelope if we found one, else empty.
        return json ?? Parsed(cards: [])
    }

    private static func parseJSON(_ text: String) -> Parsed? {
        // Cards via the tolerant AI parser (fences, prose, "cards" envelope, or a bare array).
        let cards = (try? CardJSON.parseCards(from: text)) ?? []
        // Optional deck metadata from a top-level object envelope ({"name":…, "cards":[…]}).
        var name: String?, section: String?, description: String?
        let cleaned = CardJSON.stripFences(text)
        if let object = CardJSON.balancedSpans(in: cleaned, open: "{", close: "}").first,
           let data = object.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            name = clean((json["name"] ?? json["deckName"] ?? json["title"]) as? String)
            section = clean(json["section"] as? String)
            description = clean((json["description"] ?? json["deckDescription"]) as? String)
        }
        guard !cards.isEmpty || name != nil else { return nil }
        return Parsed(name: name, section: section, deckDescription: description, cards: cards)
    }

    private static func parseCSV(_ text: String) -> [GeneratedCard] {
        CSVCodec.parse(text)
            .map { GeneratedCard(term: $0.term, definition: $0.definition) }
            .filter { !$0.term.isEmpty }
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    // MARK: Export

    /// Encodes cards as pretty-printed JSON — `{"name":…,"cards":[{"term","definition"}]}` —
    /// which round-trips back through `parse`. `name` is omitted when nil/empty.
    static func exportJSON(_ cards: [Card], name: String? = nil) -> String {
        let envelope = Envelope(
            name: clean(name),
            cards: cards.map { Envelope.Item(term: $0.term, definition: $0.definition) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(envelope)).flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"cards":[]}"#
    }

    private struct Envelope: Encodable {
        var name: String?
        var cards: [Item]
        struct Item: Encodable { var term: String; var definition: String }
    }
}

/// A JSON document wrapper so SwiftUI's `fileExporter` can write a `.json` card list
/// (mirrors `CSVDocument`).
struct JSONTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String
    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents, let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
