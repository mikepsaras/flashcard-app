import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Generate flashcards from notes/topic with AI, review them, and add to a deck.
/// Reused for both a brand-new deck and an existing one.
struct AIGenerationView: View {
    enum Target {
        case newDeck
        case existing(Deck)
    }

    let target: Target
    /// When set (new-deck flow launched from the deck editor), the deck is built from this on
    /// "Add" instead of from a name field — so the editor's name/section/color carry over, and
    /// cancelling creates nothing.
    var deckFactory: (() -> Deck)? = nil
    /// Called after cards are added (lets a presenting editor dismiss itself).
    var onAdded: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AIProvider.selectedProviderKey) private var providerRaw = AIProvider.openAI.rawValue

    @State private var deckName = ""
    @State private var prompt = ""
    @State private var count = 10
    @State private var countText = "10"
    @State private var autoCount = false
    @State private var phase: Phase = .input
    @State private var cards: [GeneratedCard] = []
    @State private var included: Set<UUID> = []
    @State private var errorText: String?
    @State private var showingFileImporter = false

    enum Phase { case input, generating, review, failed }

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .openAI }
    private var apiKey: String { KeychainStore.get(account: provider.keychainAccount) ?? "" }
    private var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    private var selectedCount: Int { cards.filter { included.contains($0.id) }.count }
    private var canGenerate: Bool { isExpanding || !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The deck being expanded, as generation context (empty for a new deck or an empty deck).
    private var existingCards: [GeneratedCard] {
        guard case .existing(let deck) = target else { return [] }
        return deck.cardArray
            .sorted { $0.createdAt < $1.createdAt }
            .map { GeneratedCard(term: $0.term, definition: $0.definition) }
    }
    /// True when adding to a deck that already has cards — the AI gets them as context and the
    /// notes field becomes optional ("just add more like these").
    private var isExpanding: Bool { !existingCards.isEmpty }

    /// Show the deck-name field only for a bare new-deck flow (not when a `deckFactory` supplies it).
    private var showsNameField: Bool {
        if case .newDeck = target, deckFactory == nil { return true }
        return false
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        for ext in ["md", "markdown"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if hasKey {
                        ToolbarItem(placement: .confirmationAction) { confirmButton }
                    }
                }
                .fileImporter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: importTypes,
                    allowsMultipleSelection: false
                ) { result in importFile(result) }
        }
        #if os(macOS)
        .frame(width: 560, height: macWindowHeight)
        #endif
    }

    #if os(macOS)
    /// The macOS sheet shrinks to fit the count-only expand input (otherwise it's a big empty
    /// box) and grows for the notes form and the review list.
    private var macWindowHeight: CGFloat {
        guard hasKey else { return 420 }
        switch phase {
        case .input:      return isExpanding ? 300 : 540
        case .generating: return 380
        case .failed:     return 440
        case .review:     return 540
        }
    }
    #endif

    private var navTitle: String {
        switch phase {
        case .input: "Generate Cards"
        case .generating: "Generating…"
        case .review: "Review Cards"
        case .failed: "Generate Cards"
        }
    }

    @ViewBuilder private var confirmButton: some View {
        switch phase {
        case .input:
            Button("Generate") { generate() }.disabled(!canGenerate)
        case .generating:
            ProgressView().controlSize(.small)
        case .review:
            Button("Add \(selectedCount)") { add() }.disabled(selectedCount == 0)
        case .failed:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        if !hasKey {
            ContentUnavailableView {
                Label("Connect an API Key", systemImage: "sparkles")
            } description: {
                Text("Add an OpenAI, Google, or Anthropic key in Settings → AI to generate cards.")
            } actions: {
                #if os(macOS)
                SettingsLink { Text("Open Settings…") }
                #endif
            }
        } else {
            switch phase {
            case .input:      inputForm
            case .generating: generatingState
            case .review:     reviewList
            case .failed:     errorState
            }
        }
    }

    private var inputForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isExpanding {
                    // Expanding a deck that already has cards: the only setting is how many to
                    // add. The deck's cards are sent as context so the AI continues it in the
                    // same format (no notes/topic, no file import, no auto count).
                    Label("New cards in the same style are added to this deck; anything it already has is skipped.", systemImage: "rectangle.stack.badge.plus")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                } else {
                    if showsNameField {
                        LabeledField(label: "Deck name", placeholder: "e.g. Spanish Basics", text: $deckName)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("Notes or topic")
                        TextEditor(text: $prompt)
                            .font(Typography.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .fieldBox()
                        Button { showingFileImporter = true } label: {
                            Label("Import from file…", systemImage: "doc.badge.plus").font(Typography.callout)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                        caption("Type or paste text, or import a .txt / .md file to use as the source.")
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        Text("Number of cards")
                            .lineLimit(1)
                            .foregroundStyle(autoCount ? .secondary : .primary)
                        Spacer(minLength: 8)
                        if !autoCount {
                            TextField("", text: $countText)
                                .multilineTextAlignment(.center)
                                .frame(width: 48)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                            #if os(macOS)
                            Stepper("", value: $count, in: 1...100)
                                .labelsHidden()
                            #endif
                        }
                        if !isExpanding {
                            Text("Auto").foregroundStyle(.secondary)
                            Toggle("Auto", isOn: $autoCount.animation())
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .fieldBox()
                    .onChange(of: countText) { _, newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(3))
                        if filtered != newValue { countText = filtered; return }
                        if let value = Int(filtered) { count = min(max(value, 1), 100) }
                    }
                    .onChange(of: count) { _, newValue in
                        if countText != String(newValue) { countText = String(newValue) }
                    }
                    caption(autoCount
                        ? "The AI decides how many cards to create. Generated with \(provider.displayName)."
                        : "Generated with \(provider.displayName). Review and edit before adding.")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.groupedBackground)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(.subheadline, weight: .medium)).foregroundStyle(.secondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 2)
    }

    private var generatingState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(autoCount
                 ? "Generating cards with \(provider.displayName)…"
                 : "Generating \(count) cards with \(provider.displayName)…")
                .font(Typography.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.groupedBackground)
    }

    /// Shown in the same centered spot as `generatingState` when a request fails, so
    /// the error is front-and-center instead of buried at the bottom of the form.
    private var errorState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.danger)
            Text("Couldn't Generate Cards")
                .font(Typography.title)
            Text(errorText ?? "Something went wrong. Please try again.")
                .font(Typography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Edit Notes") { errorText = nil; phase = .input }
                    .buttonStyle(.bordered)
                Button("Try Again") { generate() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, Theme.Spacing.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.l)
        .background(Theme.groupedBackground)
    }

    private var reviewList: some View {
        CardReviewList(cards: $cards, included: $included)
    }

    // MARK: Actions

    private func importFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let capped = String(text.prefix(20_000))   // keep request sizes sane
        prompt = prompt.isEmpty ? capped : prompt + "\n\n" + capped
        if case .newDeck = target, deckName.trimmingCharacters(in: .whitespaces).isEmpty {
            deckName = url.deletingPathExtension().lastPathComponent
        }
    }

    private func generate() {
        let key = apiKey
        let model = UserDefaults.standard.string(forKey: provider.modelDefaultsKey) ?? provider.defaultModel
        let prompt = prompt, provider = provider
        let existing = existingCards
        let requestedCount: Int? = autoCount ? nil : count
        errorText = nil
        phase = .generating
        Task {
            do {
                let result = try await CardGenerator().generate(
                    prompt: prompt, count: requestedCount, provider: provider, model: model, apiKey: key, existing: existing
                )
                cards = result
                included = Set(result.map(\.id))
                phase = .review
            } catch {
                errorText = (error as? AIError)?.errorDescription ?? error.localizedDescription
                phase = .failed
            }
        }
    }

    private func add() {
        let deck: Deck
        switch target {
        case .existing(let existing):
            deck = existing
        case .newDeck:
            if let deckFactory {
                deck = deckFactory()
            } else {
                let trimmed = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
                deck = Deck(name: trimmed.isEmpty ? "AI Deck" : trimmed)
                context.insert(deck)
            }
        }
        // Skip any card whose term was edited down to empty: the generator drops empty terms
        // at parse time, but the review list lets the user blank one out before adding.
        for card in cards where included.contains(card.id)
            && !card.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.insert(Card(term: card.term, definition: card.definition, deck: deck))
        }
        context.saveAndPersist(touching: deck)
        if let onAdded { onAdded() } else { dismiss() }
    }
}
