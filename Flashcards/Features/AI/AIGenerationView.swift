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

    enum Phase { case input, generating, review }

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .openAI }
    private var apiKey: String { KeychainStore.get(account: provider.keychainAccount) ?? "" }
    private var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    private var selectedCount: Int { cards.filter { included.contains($0.id) }.count }
    private var canGenerate: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
        .frame(width: 560, height: 540)
        #endif
    }

    private var navTitle: String {
        switch phase {
        case .input: "Generate Cards"
        case .generating: "Generating…"
        case .review: "Review Cards"
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
            }
        }
    }

    private var inputForm: some View {
        Form {
            if case .newDeck = target {
                Section("Deck name") {
                    ClearableTextField(placeholder: "e.g. Spanish Basics", text: $deckName)
                }
            }

            Section {
                TextEditor(text: $prompt)
                    .font(Typography.body)
                    .frame(minHeight: 130)
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import from file…", systemImage: "doc.badge.plus")
                }
            } header: {
                Text("Notes or topic")
            } footer: {
                Text("Type or paste text, or import a .txt / .md file to use as the source.")
            }

            Section {
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
                    Text("Auto").foregroundStyle(.secondary)
                    Toggle("Auto", isOn: $autoCount.animation())
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .onChange(of: countText) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(3))
                    if filtered != newValue { countText = filtered; return }
                    if let value = Int(filtered) { count = min(max(value, 1), 100) }
                }
                .onChange(of: count) { _, newValue in
                    if countText != String(newValue) { countText = String(newValue) }
                }
            } footer: {
                Text(autoCount
                     ? "The AI decides how many cards to create. Generated with \(provider.displayName)."
                     : "Generated with \(provider.displayName). Review and edit before adding.")
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                        .font(Typography.callout)
                }
            }
        }
        .formStyle(.grouped)
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

    private var reviewList: some View {
        List {
            Section {
                ForEach($cards) { $card in
                    HStack(alignment: .top, spacing: 12) {
                        Button { toggle(card.id) } label: {
                            Image(systemName: included.contains(card.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(included.contains(card.id) ? Theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Term", text: $card.term)
                                .font(Typography.headline)
                            TextField("Definition", text: $card.definition, axis: .vertical)
                                .font(Typography.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("\(selectedCount) of \(cards.count) selected")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: Actions

    private func toggle(_ id: UUID) {
        if included.contains(id) { included.remove(id) } else { included.insert(id) }
    }

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
        let requestedCount: Int? = autoCount ? nil : count
        errorText = nil
        phase = .generating
        Task {
            do {
                let result = try await CardGenerator().generate(
                    prompt: prompt, count: requestedCount, provider: provider, model: model, apiKey: key
                )
                cards = result
                included = Set(result.map(\.id))
                phase = .review
            } catch {
                errorText = (error as? AIError)?.errorDescription ?? error.localizedDescription
                phase = .input
            }
        }
    }

    private func add() {
        let deck: Deck
        switch target {
        case .existing(let existing):
            deck = existing
        case .newDeck:
            let trimmed = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
            deck = Deck(name: trimmed.isEmpty ? "AI Deck" : trimmed)
            context.insert(deck)
        }
        for card in cards where included.contains(card.id) {
            context.insert(Card(term: card.term, definition: card.definition, deck: deck))
        }
        deck.modifiedAt = .now
        try? context.save()
        DeckStore.persist(context)
        dismiss()
    }
}
