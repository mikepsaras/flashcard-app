import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Term/definition CSV (RFC 4180-style): quotes fields containing commas, quotes,
/// or newlines, and doubles embedded quotes.
enum CSVCodec {
    struct Row: Equatable {
        let term: String
        let definition: String
    }

    // MARK: Export

    static func export(_ cards: [Card]) -> String {
        var out = "Term,Definition\n"
        for card in cards {
            out += escape(card.term) + "," + escape(card.definition) + "\n"
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    // MARK: Import

    static func parse(_ text: String) -> [Row] {
        let records = parseRecords(text)
        var rows: [Row] = []
        for (index, record) in records.enumerated() {
            guard !record.isEmpty else { continue }
            let term = record[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = (record.count > 1 ? record[1] : "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip an optional header row.
            if index == 0, term.lowercased() == "term", definition.lowercased() == "definition" { continue }
            if term.isEmpty && definition.isEmpty { continue }
            rows.append(Row(term: term, definition: definition))
        }
        return rows
    }

    private static func parseRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
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
                    inQuotes = true; i += 1
                case ",":
                    record.append(field); field = ""; i += 1
                case "\n":
                    record.append(field); records.append(record); record = []; field = ""; i += 1
                case "\r":
                    record.append(field); records.append(record); record = []; field = ""
                    i += (i + 1 < chars.count && chars[i + 1] == "\n") ? 2 : 1
                default:
                    field.append(ch); i += 1
                }
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
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
