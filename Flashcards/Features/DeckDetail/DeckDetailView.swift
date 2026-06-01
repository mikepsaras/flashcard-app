import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DeckDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck
    var onStudy: () -> Void

    @State private var cardEditor: CardEditorMode?
    @State private var showingDeckEditor = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingAI = false

    private var sortedCards: [Card] {
        deck.cardArray.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
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
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { cardEditor = .new } label: { Label("Add Card", systemImage: "plus") }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button { showingAI = true } label: { Label("Generate Cards (AI)…", systemImage: "sparkles") }
                    if let fileURL = DeckStore.fileURL(for: deck) {
                        ShareLink(item: fileURL) { Label("Share .deck File", systemImage: "square.and.arrow.up") }
                    }
                    Divider()
                    Button { showingImporter = true } label: { Label("Import CSV…", systemImage: "square.and.arrow.down") }
                    Button { showingExporter = true } label: { Label("Export CSV…", systemImage: "square.and.arrow.up") }
                        .disabled(sortedCards.isEmpty)
                    Divider()
                    Button { showingDeckEditor = true } label: { Label("Edit Deck", systemImage: "slider.horizontal.3") }
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
            document: CSVDocument(text: CSVCodec.export(sortedCards)),
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

            HStack(spacing: Theme.Spacing.l) {
                stat(value: "\(deck.cardCount)", label: "Cards")
                stat(value: "\(deck.dueCount)", label: "Due", tint: deck.dueCount > 0 ? Theme.accent : .secondary)
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

    // MARK: Cards

    private var cardList: some View {
        List {
            Section("Cards") {
                ForEach(sortedCards) { card in
                    Button { cardEditor = .edit(card) } label: {
                        CardRowView(card: card)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteCards)

                if sortedCards.isEmpty {
                    Text("No cards yet. Tap + to add one.")
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
        let cards = sortedCards
        for index in offsets { context.delete(cards[index]) }
        deck.modifiedAt = .now
        try? context.save()
        DeckStore.persist(context)
    }
}

private struct CardRowView: View {
    let card: Card

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
            if !card.isDue {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                    .font(.system(size: 15))
                    .help("Scheduled — not due yet")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
