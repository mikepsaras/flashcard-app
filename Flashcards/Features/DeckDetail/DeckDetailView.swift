import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DeckDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck
    @Query private var allDecks: [Deck]
    var onStudy: () -> Void

    private var otherDecks: [Deck] { allDecks.filter { $0.id != deck.id } }

    @State private var cardEditor: CardEditorMode?
    @State private var showingDeckEditor = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportText = ""
    @State private var showingAI = false
    @State private var showingResetConfirm = false
    @State private var cardSearch = ""

    private var sortedCards: [Card] {
        deck.cardArray.sorted { $0.createdAt < $1.createdAt }
    }

    private var visibleCards: [Card] {
        guard !cardSearch.isEmpty else { return sortedCards }
        return sortedCards.filter {
            $0.term.localizedCaseInsensitiveContains(cardSearch)
            || $0.definition.localizedCaseInsensitiveContains(cardSearch)
        }
    }

    var body: some View {
        // The deck can be deleted out from under this view (Settings → Delete All Decks, or an
        // external file removal the watcher reconciles). Reading a deleted @Model's persisted
        // properties traps, so render nothing until RootView swaps in the placeholder.
        if deck.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            #if os(macOS)
            Divider()   // separates the header band from the list (same bg color on macOS)
            #endif
            cardList
        }
        .background(Theme.groupedBackground)
        .navigationTitle(deck.name.isEmpty ? "Untitled Deck" : deck.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // macOS allows only one search field per window toolbar, and the deck library
        // (sidebar) already owns it; a second `.searchable` here makes AppKit's NSToolbar
        // throw when a deck is selected. On iOS the library and deck are separate
        // navigation screens, so card search is safe there.
        .searchable(text: $cardSearch, prompt: "Search cards")
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { cardEditor = .new } label: { Label("New Card", systemImage: "plus") }
                    Button { showingAI = true } label: { Label("Generate Cards with AI…", systemImage: "sparkles") }
                } label: {
                    Label("Add Card", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    if let fileURL = DeckStore.fileURL(for: deck) {
                        ShareLink(item: fileURL) { Label("Share Deck File", systemImage: "square.and.arrow.up") }
                    }
                    Divider()
                    Button { showingImporter = true } label: { Label("Import CSV…", systemImage: "square.and.arrow.down") }
                    Button {
                        exportText = CSVCodec.export(sortedCards)   // build once, on demand
                        showingExporter = true
                    } label: { Label("Export CSV…", systemImage: "square.and.arrow.up") }
                        .disabled(sortedCards.isEmpty)
                    Divider()
                    Button { showingDeckEditor = true } label: { Label("Edit Deck", systemImage: "slider.horizontal.3") }
                    Button(role: .destructive) { showingResetConfirm = true } label: {
                        Label("Reset Progress", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!deck.cardArray.contains { $0.hasBeenReviewed })
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $cardEditor) { mode in
            CardEditorView(deck: deck, mode: mode)
        }
        .sheet(isPresented: $showingDeckEditor) {
            DeckEditorView(mode: .edit(deck))
        }
        .sheet(isPresented: $showingAI) {
            AIGenerationView(target: .existing(deck))
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(text: exportText),
            contentType: .commaSeparatedText,
            defaultFilename: deck.name.isEmpty ? "Flashcards" : deck.name
        ) { _ in }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .confirmationDialog(
            "Reset progress for this deck?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset Progress", role: .destructive) { resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every card becomes due again and its spaced-repetition history is cleared. This can’t be undone.")
        }
    }

    private func resetProgress() {
        for card in deck.cardArray { card.resetSchedule() }
        deck.modifiedAt = .now
        try? context.save()
        DeckStore.persist(context)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for row in CSVCodec.parse(text) where !row.term.isEmpty {
            context.insert(Card(term: row.term, definition: row.definition, deck: deck))
        }
        deck.modifiedAt = .now
        try? context.save()
        DeckStore.persist(context)
    }

    // MARK: Header

    private var header: some View {
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

            HStack(spacing: Theme.Spacing.l) {
                stat(value: "\(deck.cardCount)", label: "Cards")
                stat(value: "\(deck.dueCount)", label: "Due", tint: deck.dueCount > 0 ? Theme.accent : .secondary)
            }

            if deck.cardCount > 0 { maturityStrip }

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
    }

    private var studyButtonTitle: String {
        if deck.cardCount == 0 { return "No Cards Yet" }
        if deck.dueCount > 0 { return "Study \(deck.dueCount) Due" }
        return "Practice All Cards"
    }

    private func stat(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// This deck's card maturity — the actionable, per-deck slice of "Insights".
    private var maturityStrip: some View {
        let insights = StudyInsights.make(decks: [deck], reviewsByDay: [:], correctByDay: [:])
        return VStack(alignment: .leading, spacing: 8) {
            MaturityBar(new: insights.newCount, learning: insights.learningCount, mature: insights.matureCount)
            HStack(spacing: Theme.Spacing.m) {
                maturityLegend("New", Theme.accent, insights.newCount)
                maturityLegend("Learning", Color(hex: "#FF9500"), insights.learningCount)
                maturityLegend("Mature", Theme.success, insights.matureCount)
                Spacer(minLength: 0)
            }
        }
    }

    private func maturityLegend(_ label: String, _ color: Color, _ count: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(count)").font(Typography.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // MARK: Cards

    private var cardList: some View {
        List {
            Section("Cards") {
                ForEach(visibleCards) { card in
                    Button { cardEditor = .edit(card) } label: {
                        CardRowView(card: card)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !otherDecks.isEmpty {
                            Menu("Move to") {
                                ForEach(otherDecks) { target in
                                    Button(target.name.isEmpty ? "Untitled Deck" : target.name) { move(card, to: target) }
                                }
                            }
                        }
                        Button(role: .destructive) { deleteCard(card) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onDelete(perform: deleteCards)

                if sortedCards.isEmpty {
                    Text("No cards yet. Tap + to add one.")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                } else if visibleCards.isEmpty {
                    Text("No cards match “\(cardSearch)”.")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private func deleteCards(_ offsets: IndexSet) {
        let cards = visibleCards
        for index in offsets { context.delete(cards[index]) }
        deck.modifiedAt = .now
        try? context.save()
        DeckStore.persist(context)
    }

    private func deleteCard(_ card: Card) {
        context.delete(card)
        deck.modifiedAt = .now
        try? context.save()
        DeckStore.persist(context)
    }

    private func move(_ card: Card, to target: Deck) {
        card.deck = target
        card.modifiedAt = .now
        deck.modifiedAt = .now
        target.modifiedAt = .now
        try? context.save()
        DeckStore.persist(context)
    }
}

private struct CardRowView: View {
    let card: Card

    /// Soonest due date across the directions this card's deck actually studies.
    private var nextDue: Date {
        (card.deck?.studyReversed ?? false) ? min(card.dueDate, card.reverseDueDate) : card.dueDate
    }
    private var isDueNow: Bool { nextDue <= .now }
    private var daysUntilDue: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: nextDue)).day ?? 0
        return max(days, 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.term.isEmpty ? "—" : card.term)
                    .font(Typography.headline)
                    .lineLimit(1)
                Text(card.definition)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            scheduleBadge
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var scheduleBadge: some View {
        if !card.hasBeenReviewed {
            pill("New", color: Theme.accent)
        } else if isDueNow {
            pill("Due", color: .orange)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text("\(daysUntilDue)d")
            }
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .help("Next review \(nextDue.formatted(date: .abbreviated, time: .omitted))")
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
