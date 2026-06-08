import SwiftUI
import SwiftData

/// Edits a single existing card (term + definition) with a live Markdown/LaTeX preview. Adding
/// cards goes through the bulk composer (`BulkAddView`), so this view is edit-only.
struct CardEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck
    let card: Card

    @State private var term: String
    @State private var definition: String
    @State private var extra: String
    @State private var answerModeRaw: String

    init(deck: Deck, card: Card) {
        self.deck = deck
        self.card = card
        _term = State(initialValue: card.term)
        _definition = State(initialValue: card.definition)
        _extra = State(initialValue: card.extra)
        _answerModeRaw = State(initialValue: card.answerModeRaw)
    }

    private var canSave: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Mode", selection: Binding(
                        get: { AnswerMode(rawValue: answerModeRaw) ?? .flip },
                        set: { answerModeRaw = $0.rawValue }
                    )) {
                        ForEach(AnswerMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if AnswerMode(rawValue: answerModeRaw) == .cloze {
                        MultilineField(label: "Cloze text", placeholder: "Use {{c1::answer}} to hide text", text: $term, minHeight: 120)
                        clozeHint.font(.caption).foregroundStyle(.secondary)
                        if Cloze.hasCloze(term) { clozePreview }
                    } else {
                        MultilineField(label: "Front", placeholder: "Front of the card", text: $term, minHeight: 56)
                        MultilineField(label: "Back", placeholder: "Back of the card", text: $definition, minHeight: 120)
                        if !term.isEmpty || !definition.isEmpty {
                            markdownPreview
                        }
                    }

                    // Elaboration applies to both card kinds — a "why" shown beneath the answer in study (B1).
                    VStack(alignment: .leading, spacing: 7) {
                        MultilineField(label: "Elaboration", placeholder: "Optional — a “why”, a worked example, or a source.", text: $extra, minHeight: 72)
                        Text("Shown beneath the answer while studying. Supports Markdown & LaTeX.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    // Leech / card-health controls (S7.4) — only once the card has lapsed or been
                    // suspended, so a healthy card has nothing to act on.
                    if card.lapses > 0 || card.suspended { cardHealthSection }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Edit Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 540)
        #endif
    }

    /// Live preview of how the card's Markdown renders (the fields stay plain-text source).
    private var markdownPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Preview")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                if !term.isEmpty {
                    MarkdownText(text: term, baseSize: 17, weight: .semibold)
                }
                if !definition.isEmpty {
                    MarkdownText(text: definition, baseSize: 16, mathColor: MathColor.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .fieldBox()
            markdownHint
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The syntax hint. Each example is rendered in its own style (so you see the result), but
    /// "links" is styled text — NOT a live Markdown link, which would try to open `url:` and fail.
    private var markdownHint: Text {
        Text("Supports Markdown & LaTeX — ")
            + Text("**bold**").bold()
            + Text(", ")
            + Text("`code`").monospaced()
            + Text(", headings, lists, and math ")
            + Text("$x^2$").monospaced().foregroundStyle(Theme.accent)
            + Text(". See Help ▸ Formatting.")
    }

    /// Cloze syntax hint + live front/back preview of how the deletions render.
    private var clozeHint: Text {
        Text("Wrap text in ")
            + Text("{{c1::answer}}").monospaced().foregroundStyle(Theme.accent)
            + Text(" to hide it while studying. Add a hint with ")
            + Text("{{c1::answer::hint}}").monospaced()
            + Text(".")
    }

    private var clozePreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Preview")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                MarkdownText(text: Cloze.front(term), baseSize: 17, weight: .semibold)
                MarkdownText(text: Cloze.back(term), baseSize: 16, mathColor: MathColor.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .fieldBox()
        }
    }

    /// Leech / card-health controls (S7.4): the lapse count, plus Suspend (hold the card out of every
    /// study queue) and Reset Lapses. These act **immediately** — distinct from the term/definition
    /// edit the Save button commits — so toggling suspension doesn't depend on also saving text edits.
    private var cardHealthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: card.isLeech ? "exclamationmark.triangle.fill" : "stethoscope")
                    .foregroundStyle(card.isLeech ? .orange : .secondary)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.isLeech ? "Leech" : "Card Health")
                        .font(.system(.subheadline, weight: .semibold))
                    Text(healthSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button {
                    card.suspended.toggle()
                    persistHealthChange()
                } label: {
                    Label(card.suspended ? "Resume" : "Suspend",
                          systemImage: card.suspended ? "play.circle" : "pause.circle")
                }
                Button {
                    card.lapses = 0
                    persistHealthChange()
                } label: {
                    Label("Reset Lapses", systemImage: "arrow.counterclockwise")
                }
                .disabled(card.lapses == 0)
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .font(Typography.callout)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldBox()
    }

    private var healthSubtitle: String {
        let lapseText = card.lapses == 1 ? "Failed once" : "Failed \(card.lapses) times"
        if card.suspended {
            return card.lapses == 0 ? "Held out of study." : "\(lapseText) · held out of study."
        }
        if card.isLeech { return "\(lapseText) — consider reformulating or suspending it." }
        return lapseText + "."
    }

    /// Persists a Suspend/Reset action right away (bumping `modifiedAt` so the deck re-encodes).
    private func persistHealthChange() {
        card.modifiedAt = .now
        context.saveAndPersist(touching: deck)
    }

    private func save() {
        card.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        card.definition = definition
        card.extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        card.answerModeRaw = answerModeRaw
        card.modifiedAt = .now
        context.saveAndPersist(touching: deck)
        dismiss()
    }
}
