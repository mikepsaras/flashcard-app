import Foundation

/// How a card is presented and answered — the single per-card "answer mode" (1.8.0). Replaces the
/// old `CardType` (basic/cloze) plus the deck-level `typeToAnswer` axis with one field.
///
/// - `flip`:  see the front, reveal the back, self-grade (Again / Good / Easy).
/// - `type`:  see the front, type the answer; the app checks it (wrong → Again, correct → Good / Easy).
/// - `cloze`: `term` holds `{{c1::…}}` deletions, hidden while studying; reveal and self-grade. Cloze
///            is **intrinsic** to the card (never inherited from the deck default) and forward-only.
///
/// A deck carries a **default** of `flip` or `type` (`Deck.defaultAnswerMode`); a card either pins its
/// own mode or, with an empty `answerModeRaw`, inherits that default (see `Card.resolvedAnswerMode`).
enum AnswerMode: String, CaseIterable, Identifiable, Sendable {
    case flip, type, cloze
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flip:  "Flip & self-grade"
        case .type:  "Type the answer"
        case .cloze: "Cloze deletion"
        }
    }
    /// The modes a deck may use as its default. Cloze is per-card only — it needs `{{…}}` markup.
    static var deckDefaults: [AnswerMode] { [.flip, .type] }
}
