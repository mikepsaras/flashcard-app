import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    @State private var container: ModelContainer
    #if os(macOS)
    // Guarantees queued background deck writes land before quit (see AppDelegate).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        // No database on disk: an in-memory working copy is rebuilt from the `.deck`
        // files at every launch. Resolve the saved library folder (and start its
        // security-scoped access) before loading.
        _ = LibraryLocation.shared
        let container = DeckStore.makeContainer()
        let context = container.mainContext

        // Don't touch the user's real library when this process is only hosting unit tests
        // (each test builds its own temp container); the test host shares the app's bundle id
        // + library bookmark, so loading here would read the live files unnecessarily.
        if !DeckStore.isHostingTests {
            // 1.8.0 clean break: one-time reset of history/streaks on the first launch of this version.
            // The user keeps no cards/progress/history; old-format `.cards` files are ignored by the
            // loader (so the library starts empty), and this clears the streak / heatmap / accuracy log.
            DeckStore.runOnce("didCleanSlate1.8") {
                StudyStats.reset()
                ReviewLog.reset(at: ReviewLog.defaultURL)
            }
            // Load whatever deck files exist, converting any legacy `.deck` to `.cards` first.
            // The library is never auto-seeded and the old SwiftData store is never imported,
            // so an empty folder stays an empty library and nothing resurrects deleted decks.
            DeckStore.libraryURLs().forEach { DeckStore.migrateLegacyExtension(in: $0) }
            // Relocate a review log an earlier build left in the (visible) library folder into
            // Application Support; no-op once moved.
            ReviewLog.migrateLegacy(from: DeckStore.libraryURL())
            DeckStore.shared.loadAllFolders(into: context)
        }
        _container = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup {
            // Hosting unit tests: render nothing and run no lifecycle, so the test host never
            // starts the file watcher or persists the user's live library (which would prune it).
            if DeckStore.isHostingTests {
                Color.clear
            } else {
                RootView()
                    .environment(PersistenceMonitor.shared)
            }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 820)
        // Not `.contentMinSize`: that derived the window's min from the content, which used to be
        // pinned by a `.frame(minWidth:)` around the NavigationSplitView — and that frame broke the
        // sidebar reveal animation. The minimum size is now set via `window.minSize` in WindowConfigurator.
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                // ⌘⇧N is the app-global New Deck. Plain ⌘N is reserved for New Card, bound
                // window-scoped inside a deck (DeckDetailView) — distinct chords, so no collision.
                Button("New Deck") { AppActions.shared.newDeckTick += 1 }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            DeckFileCommands()
            CommandGroup(replacing: .help) {
                Button("Flashcards Formatting Guide") { AppActions.shared.showFormattingGuideTick += 1 }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
        }

        // Reference window for markdown/LaTeX, opened from the Help menu (⌘?).
        Window("Formatting Guide", id: "formatting-guide") {
            FormattingGuideView()
        }
        .defaultSize(width: 620, height: 740)
        #endif
    }
}

/// The selected deck, published by RootView for the File-menu commands (Save a Copy).
struct SelectedDeckFocusedKey: FocusedValueKey {
    typealias Value = Deck
}

extension FocusedValues {
    var selectedDeck: Deck? {
        get { self[SelectedDeckFocusedKey.self] }
        set { self[SelectedDeckFocusedKey.self] = newValue }
    }
}

#if os(macOS)
/// File-menu deck-file commands: Open (⌘O), Open Recent, Save a Copy (⌘⇧S). The app keeps its
/// library model (no NSDocument), so these drive the panels directly and route opens through
/// the same `DeckFileOpen` path as Finder double-clicks.
struct DeckFileCommands: Commands {
    @FocusedValue(\.selectedDeck) private var selectedDeck

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open Deck File…") { openPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Menu("Open Recent") {
                let recents = RecentDeckFiles.shared.entries
                ForEach(recents) { entry in
                    Button(entry.name) { open(entry) }
                }
                if !recents.isEmpty { Divider() }
                Button("Clear Menu") { RecentDeckFiles.shared.clear() }
                    .disabled(recents.isEmpty)
            }
            Divider()
            Button("Save a Copy…") { if let deck = selectedDeck { saveCopy(of: deck) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(selectedDeck == nil)
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DeckStore.importContentTypes.filter { $0 != .json }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Open a deck file — decks already in your library are selected, not duplicated."
        guard panel.runModal() == .OK else { return }
        AppActions.shared.requestOpen(urls: panel.urls)
    }

    private func open(_ entry: RecentDeckFiles.Entry) {
        guard let url = RecentDeckFiles.shared.url(for: entry) else { return }
        AppActions.shared.requestOpen(urls: [url])
    }

    private func saveCopy(of deck: Deck) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.flashcardsDeck]
        panel.nameFieldStringValue = deck.displayName
        panel.title = "Save a Copy"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? DeckCodec.encode(deck) else { return }
        try? data.write(to: url, options: .atomic)
        RecentDeckFiles.shared.record(url, name: deck.displayName)
    }
}
#endif
