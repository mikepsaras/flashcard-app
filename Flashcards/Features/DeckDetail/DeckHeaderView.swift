import SwiftUI

/// The deck-detail header band: optional description + category chip, a **mastery** ring with the
/// Cards/Due stats, and the Study button. Reads the deck and reports the Study tap upward.
struct DeckHeaderView: View {
    let deck: Deck
    var onStudy: () -> Void

    /// Per-deck Elo mastery (E7) — your expected success on this deck's cards; nil until enough
    /// reviews. Loaded off the render path in `.task`, so a large review log isn't parsed every redraw.
    @State private var mastery: (rate: Double, games: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if !deck.deckDescription.isEmpty {
                Text(deck.deckDescription)
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
            }

            if !deck.section.isEmpty {
                Text(deck.section)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
            }

            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                // Mastery ring leads on the left; Cards/Due sit beside it, left-aligned (no lonely gap).
                if deck.cardCount > 0 { MasteryRing(mastery: mastery?.rate) }
                stat(value: "\(deck.cardCount)", label: "Cards")
                stat(value: "\(deck.dueCount)", label: "Due", tint: deck.dueCount > 0 ? Theme.accent : .secondary)
                Spacer(minLength: 0)
            }

            PrimaryButton(
                title: studyButtonTitle,
                systemImage: "play.fill",
                tint: Color(hex: deck.colorHex)
            ) { onStudy() }
            .disabled(deck.cardCount == 0)
            .opacity(deck.cardCount == 0 ? 0.5 : 1)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.windowBackground)
        .task(id: deck.id) {
            mastery = Elo.mastery(deckRecords: ReviewLog.records(from: ReviewLog.defaultURL).filter { $0.deck == deck.id })
        }
    }

    private var studyButtonTitle: String {
        if deck.cardCount == 0 { return "No Cards Yet" }
        if deck.dueCount > 0 { return "Study \(deck.dueCount) Due" }
        return "Practice All Cards"
    }

    private func stat(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

}

/// A compact circular gauge of a deck's **mastery** (Elo expected success, 0…1) for the deck header —
/// the demonstrated-skill counterpart to recall. `nil` until there's enough reviewed data (renders
/// "—"). Not tappable: mastery isn't time-relative the way predicted recall is.
struct MasteryRing: View {
    let mastery: Double?

    private var pct: Int { Int(((mastery ?? 0) * 100).rounded()) }
    private var tint: Color { Theme.retentionTint(mastery) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                if let mastery {
                    Circle()
                        .trim(from: 0, to: max(mastery, 0.001))
                        .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(mastery == nil ? "—" : "\(pct)%")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(tint)
            }
            .frame(width: 56, height: 56)
            Text("mastery")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        #if os(macOS)
        .help("Mastery — your expected success on this deck's cards, from your review history. Needs a few reviews to appear.")
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mastery == nil ? "Mastery: not enough reviews yet" : "Mastery: \(pct) percent")
    }
}

/// A compact circular gauge of predicted recall for a deck, shown in the deck header. Tap to cycle
/// the look-ahead. `recall` is 0…1, or nil when there isn't enough reviewed data yet (renders "—").
struct RetentionRing: View {
    let recall: Double?
    /// Trailing phrase for the caption, e.g. "now" / "in 1 week".
    let phrase: String
    var onTap: () -> Void

    private var pct: Int { Int(((recall ?? 0) * 100).rounded()) }
    /// Green when strong, accent when solid, amber when slipping; grey when unmeasured.
    private var tint: Color { Theme.retentionTint(recall) }

    private static let captionFont = Font.system(size: 10, weight: .medium, design: .rounded)
    /// The longest "recall …" caption across all horizons — used to reserve a fixed width so cycling
    /// the timeframe on tap doesn't resize this column (which would shift the ring and its neighbors).
    private static let widestCaption = RetentionHorizon.allCases
        .map { "est. recall \($0.phrase)" }
        .max { $0.count < $1.count } ?? "est. recall now"

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                    if let recall {
                        Circle()
                            .trim(from: 0, to: max(recall, 0.001))
                            .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Text(recall == nil ? "—" : "\(pct)%")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(tint)
                }
                .frame(width: 56, height: 56)
                // Reserve the widest caption's width (hidden sizer) so the visible caption can change
                // on tap without resizing the column — keeps the ring and Cards/Due from shifting.
                Text(Self.widestCaption)
                    .font(Self.captionFont)
                    .hidden()
                    .overlay {
                        Text("est. recall \(phrase)")
                            .font(Self.captionFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
            }
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .help("Predicted recall \(phrase) — the share of this deck you'd remember. Tap to change the timeframe.")
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recall == nil
            ? "Predicted recall: not enough reviews yet"
            : "Predicted recall \(phrase): \(pct) percent. Tap to change the timeframe.")
    }
}
