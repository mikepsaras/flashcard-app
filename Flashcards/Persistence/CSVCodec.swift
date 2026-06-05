import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Term/definition CSV (RFC 4180-style): quotes fields containing commas, quotes,
/// or newlines, and doubles embedded quotes.
enum CSVCodec {
    struct Row: Equatable {
        let term: String
        let definition: String
        /// Optional 3rd CSV column; defaulted so existing 2-column call sites/tests are unaffected.
        var section: String = ""
    }

    // MARK: Export

    static func export(_ cards: [Card]) -> String {
        // Include the Section column only when some card is sectioned, so plain decks stay 2-column.
        let withSections = cards.contains { !$0.section.isEmpty }
        var out = withSections ? "Term,Definition,Section\n" : "Term,Definition\n"
        for card in cards {
            var line = escape(card.term) + "," + escape(card.definition)
            if withSections { line += "," + escape(card.section) }
            out += line + "\n"
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        // Quote when the field contains a delimiter/quote/newline, OR has leading or
        // trailing whitespace — otherwise import would trim that whitespace away and
        // the export→import round-trip wouldn't be lossless.
        let needsQuoting = s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
            || s.first?.isWhitespace == true || s.last?.isWhitespace == true
        if needsQuoting {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    // MARK: Import

    /// One parsed CSV field, tagged with whether it was quoted in the source.
    private struct Field { let text: String; let quoted: Bool }

    static func parse(_ text: String) -> [Row] {
        let records = parseRecords(text)
        var rows: [Row] = []
        var sawContent = false
        for record in records {
            guard !record.isEmpty else { continue }
            // Quoted fields are preserved verbatim; only unquoted fields are trimmed
            // (so a quoted "  spaced  " survives import intact).
            let term = value(record, 0)
            let definition = value(record, 1)
            let section = value(record, 2)   // optional 3rd column; "" when absent
            // Trim only for header/blank detection — never mutate quoted content.
            let termKey = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let defKey = definition.trimmingCharacters(in: .whitespacesAndNewlines)
            if termKey.isEmpty && defKey.isEmpty { continue }   // blank row (incl. leading blanks)
            // The header is the FIRST non-blank row — detected here rather than at record
            // index 0, so a leading blank line can't push the header into the data. Any accepted
            // pair of column names is recognised (Term/Front/Question + Definition/Back/Answer),
            // so a "Front,Back" or "Question,Answer" header isn't imported as a card.
            if !sawContent {
                sawContent = true
                if CardJSON.frontKeys.contains(termKey.lowercased()),
                   CardJSON.backKeys.contains(defKey.lowercased()) { continue }
            }
            rows.append(Row(term: term, definition: definition, section: section))
        }
        return rows
    }

    private static func value(_ record: [Field], _ i: Int) -> String {
        guard i < record.count else { return "" }
        let field = record[i]
        return field.quoted ? field.text : field.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseRecords(_ text: String) -> [[Field]] {
        var records: [[Field]] = []
        var record: [Field] = []
        var field = ""
        var fieldQuoted = false
        var inQuotes = false
        let chars = Array(text)
        var i = 0

        func endField() {
            record.append(Field(text: field, quoted: fieldQuoted))
            field = ""; fieldQuoted = false
        }
        func endRecord() { endField(); records.append(record); record = [] }

        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\""); i += 2; continue
                    }
                    inQuotes = false; i += 1
                } else {
                    field.append(ch); i += 1
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true; fieldQuoted = true; i += 1
                case ",":
                    endField(); i += 1
                case "\n", "\r", "\r\n":
                    // Swift coalesces a CRLF pair into a single Character, so "\r\n"
                    // (Windows / Excel exports) must be matched explicitly — it equals
                    // neither "\r" nor "\n". Lone \n (Unix) and \r (classic Mac) are
                    // their own Characters. All three end the record, consuming one.
                    endRecord(); i += 1
                default:
                    field.append(ch); i += 1
                }
            }
        }
        if !field.isEmpty || !record.isEmpty {
            endField()
            records.append(record)
        }
        return records
    }
}

/// A document wrapper so SwiftUI's `fileExporter` can write CSV.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

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
