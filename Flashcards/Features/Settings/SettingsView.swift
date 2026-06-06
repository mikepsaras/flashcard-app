import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AIProvider.selectedProviderKey) private var aiProviderRaw = AIProvider.openAI.rawValue
    @AppStorage(DefaultsKey.studySessionLimit) private var sessionLimit = 0
    @AppStorage(DefaultsKey.newCardsPerDay) private var newCardsPerDay = DefaultsKey.newCardsPerDayDefault
    @AppStorage(DefaultsKey.interleaveStudy) private var interleaveStudy = true
    @AppStorage(DefaultsKey.showImportExport) private var showImportExport = false
    @AppStorage(DefaultsKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(DefaultsKey.reminderHour) private var reminderHour = 19
    @AppStorage(DefaultsKey.reminderMinute) private var reminderMinute = 0
    @State private var apiKey = ""
    @State private var model = ""
    @State private var testStatus: TestStatus = .idle
    @State private var showingFolderPicker = false
    @State private var pendingFolderURL: URL?
    @State private var showingResetStats = false
    @State private var showingResetProgress = false
    @State private var showingDeleteAll = false

    // Hidden developer mode (unlocked by tapping the version 7×) + its test-data tools.
    @AppStorage(DefaultsKey.developerMode) private var developerMode = false
    @AppStorage(DefaultsKey.showGradeIntervals) private var showGradeIntervals = false
    @State private var versionTaps = 0
    @State private var devStatus: String?
    @State private var showingStressSheet = false
    @State private var showingSeedHistory = false
    @State private var showingRemoveTestData = false
    @State private var stressDecks = 25
    @State private var stressCards = 200
    @State private var showingLinterPreview = false
    @State private var previewCards: [GeneratedCard] = []
    @State private var previewIncluded: Set<UUID> = []

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
            advancedSection
            if developerMode { developerSection }
            helpSection
            aboutSection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingStressSheet) { stressSheet }
        .sheet(isPresented: $showingLinterPreview) { linterPreviewSheet }
        .confirmationDialog("Seed review history?", isPresented: $showingSeedHistory, titleVisibility: .visible) {
            Button("Replace Statistics", role: .destructive) { runSeedHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Overwrites your current streak, accuracy, and retention history with ~3 years of synthetic activity (so the heatmap's year picker has several years to browse). Your decks are kept.")
        }
        .confirmationDialog("Remove all test data?", isPresented: $showingRemoveTestData, titleVisibility: .visible) {
            Button("Remove Test Data", role: .destructive) { runRemoveTestData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes every deck under the “Test Data” section and resets all study statistics (the streak/accuracy/retention log is global — it can't be split into test vs. real). Your other decks are kept.")
        }
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
            Text("Clears your streak, heatmap, accuracy, and mature retention. Your decks, cards, and their review schedules are kept.")
        }
        .confirmationDialog("Reset all progress?", isPresented: $showingResetProgress, titleVisibility: .visible) {
            Button("Reset All Progress", role: .destructive) { DeckStore.shared.resetAllProgress(context) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every card in every deck becomes due again and its spaced-repetition history is cleared — due dates, maturity, and recall. Your cards and decks are kept. This can’t be undone.")
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
            Picker(selection: $newCardsPerDay) {
                Text("Unlimited").tag(0)
                Text("10").tag(10)
                Text("20").tag(20)
                Text("30").tag(30)
                Text("50").tag(50)
            } label: {
                Label("New cards per day", systemImage: "sparkles")
            }
            Toggle(isOn: $interleaveStudy) {
                Label("Interleave topics", systemImage: "shuffle")
            }
        } header: {
            Text("Studying")
        } footer: {
            Text("A session cap studies the most-due cards in batches. New cards are introduced gradually, up to the daily limit, so a big import doesn’t flood your reviews. Interleaving mixes decks and sections so related cards are spread out. Grading buttons (2 or 4) are set per deck, in the deck’s editor.")
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
            Button("Reset All Progress") { showingResetProgress = true }
            Button("Delete All Decks", role: .destructive) { showingDeleteAll = true }
        } header: {
            Text("Data")
        } footer: {
            Text("Reset Statistics clears your activity history (streak, heatmap, accuracy, mature retention). Reset All Progress restarts every card's review schedule across all decks — due dates, maturity, and recall — keeping the cards. Delete All Decks removes every deck and card permanently.")
        }
    }

    private var advancedSection: some View {
        Section {
            Toggle("Show JSON / CSV import & export", isOn: $showImportExport)
        } header: {
            Text("Advanced")
        } footer: {
            Text("Adds buttons for importing cards from and exporting cards to JSON or CSV files — in a deck’s menus and when creating a deck. Opening and sharing .cards deck files stays available either way.")
        }
    }

    private var helpSection: some View {
        Section {
            #if os(macOS)
            Button { AppActions.shared.showFormattingGuideTick += 1 } label: {
                Label("Formatting Guide", systemImage: "textformat")
            }
            #else
            NavigationLink {
                FormattingGuideView()
            } label: {
                Label("Formatting Guide", systemImage: "textformat")
            }
            #endif
        } header: {
            Text("Help")
        } footer: {
            Text("The Markdown and LaTeX syntax you can use on card fronts and backs.")
        }
    }

    // MARK: About + hidden developer mode

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var appBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }

    private var aboutSection: some View {
        Section {
            // A plain Button (not .onTapGesture, which is flaky on macOS Form rows) so the hidden
            // 7-tap unlock registers reliably — while still looking like an ordinary row.
            Button(action: registerVersionTap) {
                HStack {
                    Text("Version").foregroundStyle(.primary)
                    Spacer()
                    Text("\(appVersion) (\(appBuild))").foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("About")
        } footer: {
            if developerMode {
                Text("Developer mode is on.")
            } else if versionTaps >= 4 {
                let left = 7 - versionTaps
                Text("\(left) more tap\(left == 1 ? "" : "s") to enable developer mode…")
            }
        }
    }

    private var developerSection: some View {
        Section {
            Button { runLoadSample() } label: { Label("Load sample library", systemImage: "square.stack.3d.up.fill") }
            Button { runLoadPhase0() } label: { Label("Load Phase 0 test set", systemImage: "flask.fill") }
            Button { showingLinterPreview = true } label: { Label("Preview card linter (S0.4)", systemImage: "checklist") }
            Button { showingStressSheet = true } label: { Label("Stress test…", systemImage: "gauge.high") }
            Button { showingSeedHistory = true } label: { Label("Seed review history", systemImage: "calendar.badge.clock") }
            Button(role: .destructive) { showingRemoveTestData = true } label: { Label("Remove all test data", systemImage: "trash") }
            Toggle(isOn: $showGradeIntervals) {
                Label("Show projected intervals while studying", systemImage: "calendar.badge.clock")
            }
            Button("Disable Developer Mode") { developerMode = false; showGradeIntervals = false; devStatus = nil }
        } header: {
            Text("Developer")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                // Live queue readout — confirms the S0.2 throttle (watch this climb to the limit and
                // stop) and the S0.3 toggle. Refreshes whenever this screen re-renders.
                Text("New introduced today: **\(StudyStats.newCardsIntroducedToday())** of \(newCardsPerDay == 0 ? "∞" : String(newCardsPerDay))  ·  interleave \(interleaveStudy ? "on" : "off")")
                    .monospacedDigit()
                Text(devStatus ?? "“Load Phase 0 test set” builds three decks (under “Test Data”) for the new study-queue behaviors; “Preview card linter” shows the AI quality warnings without an API call. See PHASE0-TESTING.md.")
            }
        }
    }

    private var stressSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Small — 5 × 50") { stressDecks = 5; stressCards = 50 }
                    Button("Medium — 25 × 200") { stressDecks = 25; stressCards = 200 }
                    Button("Large — 100 × 1,000") { stressDecks = 100; stressCards = 1000 }
                } header: { Text("Presets") }
                Section {
                    Stepper("Decks: \(stressDecks)", value: $stressDecks, in: 1...200)
                    Stepper("Cards per deck: \(stressCards)", value: $stressCards, in: 0...5000, step: 50)
                } footer: {
                    Text("Total: \((stressDecks * stressCards).formatted()) cards. Large sizes take a moment to generate and write to disk.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Stress Test")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingStressSheet = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Generate") { runStress() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private func registerVersionTap() {
        guard !developerMode else { return }
        versionTaps += 1
        if versionTaps >= 7 {
            developerMode = true
            versionTaps = 0
            devStatus = "Developer mode enabled."
        }
    }

    private func runLoadSample() {
        let r = DeveloperTools.loadSampleLibrary(into: context)
        context.saveAndPersist()
        devStatus = "Loaded \(r.decks) decks · \(r.cards) cards. Tip: also “Seed review history” for full Insights."
    }

    private func runLoadPhase0() {
        let r = DeveloperTools.loadPhase0Scenario(into: context)
        context.saveAndPersist()
        devStatus = "Loaded \(r.decks) Phase 0 decks · \(r.cards) cards. Study them, then re-open this screen to watch the “new introduced today” counter. Tip: also “Seed review history” for the retention metrics."
    }

    /// Hosts the shared `CardReviewList` with deliberately-flawed sample cards, so the S0.4 quality
    /// linter's warnings are visible without a live API call. Reseeded fresh on each open.
    private var linterPreviewSheet: some View {
        NavigationStack {
            CardReviewList(cards: $previewCards, included: $previewIncluded)
                .navigationTitle("Linter preview")
                .onAppear {
                    previewCards = DeveloperTools.sampleCardsWithIssues()
                    previewIncluded = Set(previewCards.map(\.id))
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingLinterPreview = false } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 460)
        #endif
    }

    private func runStress() {
        showingStressSheet = false
        let r = DeveloperTools.stressTest(decks: stressDecks, cardsPerDeck: stressCards, into: context)
        context.saveAndPersist()
        devStatus = "Generated \(r.decks) decks · \(r.cards.formatted()) cards."
    }

    private func runSeedHistory() {
        DeveloperTools.seedReviewHistory()
        devStatus = "Seeded ~3 years of review history."
    }

    private func runRemoveTestData() {
        let n = DeveloperTools.removeAllTestData(into: context)
        context.saveAndPersist()
        devStatus = "Removed \(n) test deck\(n == 1 ? "" : "s") and cleared seeded stats."
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
