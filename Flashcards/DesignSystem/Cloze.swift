import Foundation

/// Renders cloze-deletion text (`{{c1::answer}}` or `{{c1::answer::hint}}`) for study. v1 is "hide-all":
/// the front hides every deletion (showing its hint, or "[…]"), the back reveals every answer — so a
/// cloze card is one whole-card unit (decision #8). Per-cloze independent units/scheduling are a later
/// enhancement. Pure + unit-tested.
enum Cloze {
    /// One deletion, lazily matched to the first closing braces so multiple clozes on a line each match.
    private static let pattern = "\\{\\{c\\d+::(.*?)\\}\\}"

    /// Whether the text contains any cloze deletion.
    static func hasCloze(_ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// The study front: each deletion replaced by its hint (`[hint]`) or a blank (`[…]`).
    static func front(_ text: String) -> String {
        replacingDeletions(in: text) { content in
            let parts = content.components(separatedBy: "::")
            return parts.count > 1 && !parts[1].isEmpty ? "[\(parts[1])]" : "[…]"
        }
    }

    /// The study back: each deletion replaced by its answer (the hint, if any, dropped).
    static func back(_ text: String) -> String {
        replacingDeletions(in: text) { content in
            content.components(separatedBy: "::").first ?? content
        }
    }

    private static func replacingDeletions(in text: String, _ transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform(ns.substring(with: match.range(at: 1)))
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
