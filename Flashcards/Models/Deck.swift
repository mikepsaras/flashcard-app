import Foundation
import SwiftData

/// A named collection of cards.
///
/// CloudKit-safe: scalars defaulted, relationship optional with a declared
/// inverse, delete rule `.cascade` (deleting a deck removes its cards).
@Model
final class Deck {
    var id: UUID = UUID()
    var name: String = ""
    var deckDescription: String = ""
    var colorHex: String = "#3478F6"
    /// Small label shown above the answer side of a card (e.g. "Definition",
    /// "Capital", "Translation"). Customizable per deck.
    var backLabel: String = "Definition"
    /// When true, each card is also studied definition → term, with its own independent
    /// spaced-repetition schedule.
    var studyReversed: Bool = false
    /// Which grading controls this deck uses while studying — 2-button (Know / Don't know)
    /// or 4-button (Again / Hard / Good / Easy), as a `GradingMode` raw value. Empty means
    /// "not explicitly chosen" — a deck saved before this setting existed — and inherits the
    /// legacy default (see `gradingMode`). Decks created in-app always store a concrete value.
    var gradingModeRaw: String = ""
    /// The single section this deck belongs to; the library groups decks into sections by it.
    /// Empty ⇒ "Uncategorized". CloudKit-safe: defaulted.
    var section: String = ""
    /// Ordered card-section names *within* this deck (Reminders-style). Distinct from `section`
    /// above (which groups the deck in the library): this lets an empty section persist and sets
    /// the header order; each `Card.section` references one of these by name. CloudKit-safe.
    var sectionOrder: [String] = []
    /// Whether each card's section appears as a chip on the study card. Per deck. CloudKit-safe.
    var showSectionsInStudy: Bool = true
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card]?

    init(
        name: String = "",
        deckDescription: String = "",
        colorHex: String = "#3478F6",
        backLabel: String = "Definition",
        studyReversed: Bool = false,
        gradingMode: GradingMode = .twoButton,
        section: String = "",
        sectionOrder: [String] = [],
        showSectionsInStudy: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.deckDescription = deckDescription
        self.colorHex = colorHex
        self.backLabel = backLabel
        self.studyReversed = studyReversed
        self.gradingModeRaw = gradingMode.rawValue
        self.section = section
        self.sectionOrder = sectionOrder
        self.showSectionsInStudy = showSectionsInStudy
        self.createdAt = .now
        self.modifiedAt = .now
        self.cards = []
    }
}

extension Deck {
    /// Non-optional view of the cards relationship for convenient use in the UI.
    var cardArray: [Card] { cards ?? [] }
    var cardCount: Int { cardArray.count }

    // MARK: Card sections (within-deck grouping)

    /// One section's cards for the deck-detail UI; `name == ""` is the unsectioned area.
    struct SectionGroup: Identifiable {
        let name: String
        let cards: [Card]
        var isUnsectioned: Bool { name.isEmpty }
        var id: String { name.isEmpty ? "\u{0}unsectioned" : name }
    }

    /// Cards grouped for display: the unsectioned area first (when non-empty), then each named
    /// section in `sectionOrder` (empty sections included so they persist), then any orphan
    /// sections (a card whose section isn't in `sectionOrder`, e.g. from an external edit). Cards
    /// within a group are ordered by `sortOrder`, then `createdAt` as a stable tiebreak.
    var sectionGroups: [SectionGroup] {
        let bySection = Dictionary(grouping: cardArray) { $0.section }
        func ordered(_ cards: [Card]) -> [Card] {
            cards.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
        }
        var groups: [SectionGroup] = []
        let unsectioned = ordered(bySection[""] ?? [])
        if !unsectioned.isEmpty { groups.append(SectionGroup(name: "", cards: unsectioned)) }
        for name in sectionOrder {
            groups.append(SectionGroup(name: name, cards: ordered(bySection[name] ?? [])))
        }
        let known = Set(sectionOrder + [""])
        for name in bySection.keys.filter({ !known.contains($0) }).sorted() {
            groups.append(SectionGroup(name: name, cards: ordered(bySection[name] ?? [])))
        }
        return groups
    }

    /// The next `sortOrder` for appending a card to the end of `section` (its max + 1).
    func nextSortOrder(inSection section: String) -> Int {
        (cardArray.filter { $0.section == section }.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Native `List` reorder within a section: applies an `onMove` (offsets → destination) to the
    /// section's cards and renumbers their `sortOrder`. Pure model mutation (the caller persists).
    func moveCards(inSection section: String, from source: IndexSet, to destination: Int) {
        var cards = (sectionGroups.first { $0.name == section }?.cards) ?? []
        cards.move(fromOffsets: source, toOffset: destination)
        for (index, card) in cards.enumerated() { card.sortOrder = index }
    }

    /// Moves the named section up (`-1`) or down (`+1`) in `sectionOrder`. No-op at the ends.
    func moveSection(_ name: String, by offset: Int) {
        guard let index = sectionOrder.firstIndex(of: name) else { return }
        let destination = index + offset
        guard destination >= 0, destination < sectionOrder.count else { return }
        sectionOrder.swapAt(index, destination)
    }

    /// The deck's name for display, with a placeholder when it's blank. Centralizes the
    /// "Untitled Deck" fallback the UI would otherwise repeat at every call site.
    var displayName: String { name.isEmpty ? "Untitled Deck" : name }

    /// The deck's grading controls (2- or 4-button), backed by `gradingModeRaw`. An empty raw
    /// value (a deck file predating this setting) resolves to the legacy global default, so
    /// existing decks don't silently change.
    var gradingMode: GradingMode {
        get { resolvedGradingMode() }
        set { gradingModeRaw = newValue.rawValue }
    }

    /// Resolves the grading mode; takes `defaults` so tests don't read the app's real prefs.
    func resolvedGradingMode(defaults: UserDefaults = .standard) -> GradingMode {
        GradingMode(rawValue: gradingModeRaw)
            ?? GradingMode(rawValue: GradingMode.legacyDefaultRaw(defaults))
            ?? .twoButton
    }

    /// Every review unit this deck offers: forward for each card, plus a reverse unit
    /// per card when reverse study is enabled.
    var allReviewItems: [ReviewItem] {
        cardArray.flatMap { card in
            studyReversed
                ? [ReviewItem(card: card, direction: .forward), ReviewItem(card: card, direction: .reverse)]
                : [ReviewItem(card: card, direction: .forward)]
        }
    }

    /// Review units due now (a card can contribute twice when both directions are due).
    var dueReviewItems: [ReviewItem] {
        allReviewItems.filter { $0.card.isDue($0.direction) }
    }

    var dueCount: Int { dueReviewItems.count }
}
