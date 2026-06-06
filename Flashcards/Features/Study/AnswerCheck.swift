import Foundation

/// Compares a learner's typed answer to the expected answer for type-in study (B3). Forgiving about
/// case and runs of whitespace (and a single trailing period, often typed reflexively), strict about
/// everything else — accents included, since those are usually meaningful in the kind of short answers
/// type-in suits (vocabulary, terms, facts). The learner still self-grades after the reveal, so a
/// near-miss can be accepted or overridden either way; this just drives the ✓/✗ hint. Pure + static
/// ⇒ unit-tested.
enum AnswerCheck {
    /// Whether `typed` should count as matching `expected`. Empty/blank input never matches.
    static func matches(_ typed: String, _ expected: String) -> Bool {
        let a = normalize(typed)
        return !a.isEmpty && a == normalize(expected)
    }

    /// Lowercased, with outer/inner whitespace runs collapsed to single spaces and a lone trailing
    /// period dropped — the normal form both sides are compared in.
    static func normalize(_ s: String) -> String {
        let collapsed = s.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.hasSuffix(".") ? String(collapsed.dropLast()) : collapsed
    }
}
