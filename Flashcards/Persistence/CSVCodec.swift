import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// RFC-4180 field escaping shared by the deck CSV and the Insights CSV: quote when the field holds a
/// delimiter, quote, newline, or leading/trailing whitespace (so an export→import round-trip is
/// lossless), doubling embedded quotes.
private func csvEscape(_ s: String) -> String {
    let needsQuoting = s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
        || s.first?.isWhitespace == true || s.last?.isWhitespace == true
    return needsQuoting ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
}

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
            var line = csvEscape(card.term) + "," + csvEscape(card.definition)
            if withSections { line += "," + csvEscape(card.section) }
            out += line + "\n"
        }
        return out
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
                // Header detection uses the multi-letter column names only — a 1-letter alias like
                // "q"/"a" is too likely to be a real first card (e.g. a headerless "Q,A" file), so
                // those don't count as a header row.
                let frontHeaders = CardJSON.frontKeys.filter { $0.count > 1 }
                let backHeaders = CardJSON.backKeys.filter { $0.count > 1 }
                if frontHeaders.contains(termKey.lowercased()),
                   backHeaders.contains(defKey.lowercased()) { continue }
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

/// Exports the whole Insights page as one CSV: a Summary block, then By-deck / By-category /
/// By-section tables, then the daily activity log — each its own header + rows, separated by a
/// blank line (a common "dashboard → spreadsheet" shape). Pure + static, so it's unit-tested.
enum StatsCSV {
    static func export(insights: StudyInsights, reviewsByDay: [String: Int], correctByDay: [String: Int]) -> String {
        var out = ""
        func row(_ fields: [String]) { out += fields.map(csvEscape).joined(separator: ",") + "\n" }
        func blank() { out += "\n" }

        row(["Metric", "Value"])
        row(["Current streak (days)", "\(insights.currentStreak)"])
        row(["Longest streak (days)", "\(insights.longestStreak)"])
        row(["Reviewed today", "\(insights.reviewsToday)"])
        row(["Reviewed this week", "\(insights.reviewsThisWeek)"])
        row(["Reviewed all-time", "\(insights.reviewsAllTime)"])
        row(["Accuracy", pct(insights.accuracyAllTime)])
        row(["Predicted recall now", pct(insights.predictedRetention)])
        row(["Mature retention", pct(insights.trueRetention)])
        row(["Total cards", "\(insights.totalCards)"])
        row(["New", "\(insights.newCount)"])
        row(["Learning", "\(insights.learningCount)"])
        row(["Mature", "\(insights.matureCount)"])
        row(["Due now", "\(insights.dueNow)"])
        row(["Due in 7 days", "\(insights.dueThisWeek)"])

        if !insights.perDeck.isEmpty {
            blank(); row(["Deck", "Cards", "Due", "New", "Learning", "Mature"])
            for d in insights.perDeck.sorted(by: { ($0.due, $0.totalCards) > ($1.due, $1.totalCards) }) {
                row([d.name, "\(d.totalCards)", "\(d.due)", "\(d.newCount)", "\(d.learningCount)", "\(d.matureCount)"])
            }
        }
        if !insights.categories.isEmpty {
            blank(); row(["Subject", "Cards", "Due", "New", "Learning", "Mature"])
            for c in insights.categories {
                row([c.name, "\(c.totalCards)", "\(c.due)", "\(c.newCount)", "\(c.learningCount)", "\(c.matureCount)"])
            }
        }
        if !insights.sections.isEmpty {
            blank(); row(["Deck", "Section", "Cards", "Due", "New", "Learning", "Mature"])
            for s in insights.sections {
                row([s.deckName, s.section.isEmpty ? "(none)" : s.section, "\(s.totalCards)", "\(s.due)", "\(s.newCount)", "\(s.learningCount)", "\(s.matureCount)"])
            }
        }
        if !reviewsByDay.isEmpty {
            blank(); row(["Date", "Reviews", "Correct"])
            for day in reviewsByDay.keys.sorted() {
                row([day, "\(reviewsByDay[day] ?? 0)", "\(correctByDay[day] ?? 0)"])
            }
        }
        return out
    }

    private static func pct(_ value: Double?) -> String {
        guard let value else { return "" }
        return "\(Int((value * 100).rounded()))%"
    }
}
