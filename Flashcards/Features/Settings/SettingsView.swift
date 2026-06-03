import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AIProvider.selectedProviderKey) private var aiProviderRaw = AIProvider.openAI.rawValue
    @AppStorage(DefaultsKey.studySessionLimit) private var sessionLimit = 0
    @AppStorage(DefaultsKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(DefaultsKey.reminderHour) private var reminderHour = 19
    @AppStorage(DefaultsKey.reminderMinute) private var reminderMinute = 0
    @State private var apiKey = ""
    @State private var model = ""
    @State private var testStatus: TestStatus = .idle
    @State private var showingFolderPicker = false
    @State private var pendingFolderURL: URL?
    @State private var showingResetStats = false
    @State private var showingDeleteAll = false

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date() },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                reminderHour = c.hour ?? 19
                reminderMinute = c.minute ?? 0
            }
        )
    }

    private enum TestStatus: Equatable { case idle, testing, ok, failed(String) }
    private var aiProvider: AIProvider { AIProvider(rawValue: aiProviderRaw) ?? .openAI }

    var body: some View {
        Form {
            studyingSection
            remindersSection
            aiSection
            storageSection
            dataSection
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            handleFolderPick(result)
        }
        .confirmationDialog(
            pendingFolderURL.map { "Use “\($0.lastPathComponent)” for your decks?" } ?? "",
            isPresented: Binding(get: { pendingFolderURL != nil }, set: { if !$0 { cancelPendingFolder() } }),
            titleVisibility: .visible,
            presenting: pendingFolderURL
        ) { url in
            Button("Move My Decks Here") { applyFolder(url, move: true) }
            Button("Use the Decks Already Here") { applyFolder(url, move: false) }
            Button("Cancel", role: .cancel) { cancelPendingFolder() }
        } message: { _ in
            Text("Move copies your current decks into this folder. Use loads the decks already there and leaves your current ones where they are.")
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset statistics?", isPresented: $showingResetStats, titleVisibility: .visible) {
            Button("Reset Statistics", role: .destructive) { StudyStats.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears your study streak and review history. Your decks and cards are kept.")
        }
        .confirmationDialog("Delete all decks?", isPresented: $showingDeleteAll, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                DeckStore.shared.deleteAllDecks(context)
                StudyStats.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently deletes every deck and card, and clears your statistics. This can’t be undone.")
        }
        .onAppear { loadAI() }
        .task {
            // Resync the reminder toggle if notification permission was revoked in System
            // Settings (otherwise it stays "on" while no nudges ever fire).
            if remindersEnabled, !(await StudyReminders.isAuthorized()) {
                remindersEnabled = false
            }
        }
        .onChange(of: aiProviderRaw) { _, _ in loadAI() }
        .onChange(of: apiKey) { _, newValue in
            KeychainStore.set(newValue, account: aiProvider.keychainAccount)
            testStatus = .idle
        }
        .onChange(of: model) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: aiProvider.modelDefaultsKey)
        }
        .onChange(of: remindersEnabled) { _, on in
            if on {
                Task {
                    if await StudyReminders.requestAuthorization() {
                        StudyReminders.schedule(hour: reminderHour, minute: reminderMinute)
                    } else {
                        remindersEnabled = false   // permission denied → revert the toggle
                    }
                }
            } else {
                StudyReminders.cancel()
            }
        }
        .onChange(of: reminderHour) { _, _ in
            if remindersEnabled { StudyReminders.schedule(hour: reminderHour, minute: reminderMinute) }
        }
        .onChange(of: reminderMinute) { _, _ in
            if remindersEnabled { StudyReminders.schedule(hour: reminderHour, minute: reminderMinute) }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
    }

    private var studyingSection: some View {
        Section {
            Picker(selection: $sessionLimit) {
                Text("Unlimited").tag(0)
                Text("10").tag(10)
                Text("20").tag(20)
                Text("30").tag(30)
                Text("50").tag(50)
            } label: {
                Label("Cards per session", systemImage: "rectangle.stack")
            }
        } header: {
            Text("Studying")
        } footer: {
            Text("A session cap studies the most-due cards in batches. Grading buttons (2 or 4) are set per deck, in the deck’s editor.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Daily reminder", isOn: $remindersEnabled)
            if remindersEnabled {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("A daily nudge to review. Notifications stay on this device.")
        }
    }

    private var aiSection: some View {
        Section {
            Picker("Provider", selection: $aiProviderRaw) {
                ForEach(AIProvider.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            SecureField("API key", text: $apiKey)
            TextField("Model", text: $model, prompt: Text(aiProvider.defaultModel))
                .font(.system(.body, design: .monospaced))
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
            HStack {
                Button { testConnection() } label: {
                    Label("Test connection", systemImage: "checkmark.seal")
                }
                .disabled(apiKey.isEmpty || testStatus == .testing)
                Spacer()
                testStatusView
            }
        } header: {
            Text("AI Card Generation")
        } footer: {
            Text("Your key is stored in this device's Keychain and used only to call \(aiProvider.displayName) directly. Get one at \(aiProvider.keyConsoleURL).")
        }
    }

    private var storageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 3) {
                Text("Library folder")
                Text(LibraryLocation.shared.current.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Choose Folder…") { showingFolderPicker = true }
            if LibraryLocation.shared.isCustom {
                Button("Use Default Folder") { useDefaultFolder() }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Where your deck files are saved and loaded. When you choose a folder you can move your current decks into it, or just use the decks already there.")
        }
    }

    private var dataSection: some View {
        Section {
            Button("Reset Statistics") { showingResetStats = true }
            Button("Delete All Decks", role: .destructive) { showingDeleteAll = true }
        } header: {
            Text("Data")
        } footer: {
            Text("Reset Statistics clears your streak and review history but keeps your decks. Delete All Decks permanently removes every deck and card, and clears statistics.")
        }
    }

    @ViewBuilder private var testStatusView: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
                .font(Typography.caption)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(Theme.danger)
                .font(Typography.caption)
                .lineLimit(2)
        }
    }

    private func loadAI() {
        apiKey = KeychainStore.get(account: aiProvider.keychainAccount) ?? ""
        model = UserDefaults.standard.string(forKey: aiProvider.modelDefaultsKey) ?? ""
        testStatus = .idle
    }

    private func handleFolderPick(_ result: Result<URL, Error>) {
        guard let url = try? result.get() else { return }
        _ = url.startAccessingSecurityScopedResource()   // needed to read/write the folder
        pendingFolderURL = url                            // ask how to use it
    }

    private func applyFolder(_ url: URL, move: Bool) {
        let old = LibraryLocation.shared.current
        // Commit the new location FIRST. setCustom only changes the active folder if it can
        // actually persist the choice (write the security-scoped bookmark); if it can't, bail
        // without touching the in-memory library — otherwise we'd swap in the new folder's
        // decks while still pointed at `old`, and the next persist would write them into `old`.
        // The folder change drives RootView's reconcile, but only on the next render pass —
        // after the migrate/switch below has populated the new folder — so it stays a no-op.
        guard LibraryLocation.shared.setCustom(url) else {
            cancelPendingFolder()
            return
        }
        // setCustom now holds the session-long access; release the extra one from handleFolderPick.
        url.stopAccessingSecurityScopedResource()
        if move {
            // Move the decks in (merging any already there) so the new folder is populated
            // before any reconcile can run against it.
            DeckStore.shared.migrate(from: old, to: url, context: context)
        } else {
            DeckStore.shared.switchFolder(to: url, context: context)
        }
        pendingFolderURL = nil
    }

    private func cancelPendingFolder() {
        pendingFolderURL?.stopAccessingSecurityScopedResource()
        pendingFolderURL = nil
    }

    private func useDefaultFolder() {
        // Revert to ~/Documents/Flashcards and load its decks (the custom folder is left intact).
        DeckStore.shared.switchFolder(to: LibraryLocation.defaultFolder(), context: context)
        LibraryLocation.shared.resetToDefault()
    }

    private func testConnection() {
        let key = apiKey
        let usedModel = model.isEmpty ? aiProvider.defaultModel : model
        let provider = aiProvider
        testStatus = .testing
        Task {
            do {
                _ = try await CardGenerator().generate(
                    prompt: "Make one flashcard about the capital of France.",
                    count: 1, provider: provider, model: usedModel, apiKey: key
                )
                testStatus = .ok
            } catch {
                testStatus = .failed((error as? AIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

#Preview {
    SettingsView()
}
