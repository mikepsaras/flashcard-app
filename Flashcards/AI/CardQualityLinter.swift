import Foundation

/// Heuristic, non-blocking quality checks for AI-suggested cards, surfaced as gentle warnings in
/// the review step (S0.4). It nudges toward well-formed cards — atomic, not circular, not a buried
/// list — but never blocks: the user can keep or edit any card. Deliberately conservative, to keep
/// false positives off good cards. Pure + static ⇒ unit-testable.
enum CardQualityLinter {

    /// A single quality nudge for one card.
    enum Warning: String, CaseIterable, Hashable, Sendable {
        case longAnswer    // answer long enough to likely pack several facts
        case enumeration   // the card is (or asks for) a list rather than one fact
        case circular      // the answer restates the term, so it may not test recall
        case shortAnswer   // missing / trivially short answer
        case duplicate     // another suggested card shares the same (normalized) term

        var message: String {
            switch self {
            case .longAnswer:  "Long answer — consider splitting into smaller, atomic cards."
            case .enumeration: "Looks like a list — separate cards recall better than enumerations."
            case .circular:    "The answer repeats the term, so it may not test recall."
            case .shortAnswer: "The answer is missing or very short."
            case .duplicate:   "Another card has a very similar term."
            }
        }
    }

    /// Answer word count above which a card probably packs more than one fact.
    static let longAnswerWordCount = 40
    /// Below this term length, term-in-answer is too noisy to flag as circular (e.g. short acronyms).
    static let circularMinTermLength = 5

    /// Warnings per card id (absent id ⇒ no warnings). Duplicate detection spans the whole batch,
    /// catching near-duplicates that slip past the generator's exact-term dedup (punctuation/case).
    static func warnings(for cards: [GeneratedCard]) -> [UUID: [Warning]] {
        var idsByNormalizedTerm: [String: [UUID]] = [:]
        for card in cards { idsByNormalizedTerm[normalize(card.term), default: []].append(card.id) }
        let duplicated = Set(idsByNormalizedTerm.values.filter { $0.count > 1 }.flatMap { $0 })

        var result: [UUID: [Warning]] = [:]
        for card in cards {
            var warnings: [Warning] = []
            let answer = card.definition.trimmingCharacters(in: .whitespacesAndNewlines)

            if answer.count < 2 { warnings.append(.shortAnswer) }
            else if wordCount(answer) > longAnswerWordCount { warnings.append(.longAnswer) }

            if looksLikeList(card) { warnings.append(.enumeration) }
            if isCircular(term: card.term, answer: answer) { warnings.append(.circular) }
            if duplicated.contains(card.id) { warnings.append(.duplicate) }

            if !warnings.isEmpty { result[card.id] = warnings }
        }
        return result
    }

    // MARK: Heuristics

    /// Lowercased, non-alphanumerics → spaces, whitespace collapsed — so "What is HTTP?" and
    /// "what is http" compare equal.
    static func normalize(_ s: String) -> String {
        let mapped = s.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    /// The answer is a bulleted/numbered list of ≥3 items, or the term explicitly asks for a list.
    static func looksLikeList(_ card: GeneratedCard) -> Bool {
        let lines = card.definition.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let bulletLines = lines.filter { line in
            line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") || isOrderedListItem(line)
        }
        if bulletLines.count >= 3 { return true }
        let t = card.term.lowercased()
        return t.hasPrefix("list ") || t.contains("list of ") || t.contains("what are the ")
            || t.contains("name the ") || t.contains("give examples")
    }

    /// A leading ordered-list marker — one or more digits then "." or ")", e.g. "1." or "10)". Matching
    /// only the first two characters would miss two-digit markers ("10."), under-counting long lists.
    private static func isOrderedListItem(_ line: String) -> Bool {
        guard line.first?.isNumber == true else { return false }
        let afterDigits = line.drop(while: \.isNumber)
        return afterDigits.first == "." || afterDigits.first == ")"
    }

    /// The answer restates the term. Skips short all-caps acronyms (which legitimately appear in
    /// their own expansion, e.g. "HTML — HyperText Markup Language") and very short terms.
    static func isCircular(term: String, answer: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        if trimmed == trimmed.uppercased() && trimmed.count <= 6 { return false }
        let normalizedTerm = normalize(term)
        guard normalizedTerm.count >= circularMinTermLength else { return false }
        // Whole-token match, not raw substring, so "state" doesn't fire on "statement". `normalize`
        // already collapses to single-space-separated lowercased tokens, so padding both sides with a
        // space matches the term only at token boundaries.
        return " \(normalize(answer)) ".contains(" \(normalizedTerm) ")
    }
}
