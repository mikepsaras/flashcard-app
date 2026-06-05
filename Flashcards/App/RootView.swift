import SwiftUI
import SwiftData

/// Sidebar selection: the cross-deck Today queue, or a specific deck.
enum SidebarItem: Hashable {
    case today
    case insights
    case deck(PersistentIdentifier)
}

/// Adaptive root: sidebar (Today + decks) + detail on macOS/iPad, collapsing to a
/// stack on iPhone. Study is presented over everything via a `StudyPlan`.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(PersistenceMonitor.self) private var persistenceMonitor
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @State private var studyPlan: StudyPlan?
    @State private var watcher = DeckFolderWatcher()

    // Auto-select Today on macOS; start at the list on iPhone.
    #if os(macOS)
    @State private var selection: SidebarItem? = .today
    #else
    @State private var selection: SidebarItem?
    #endif

    private var selectedDeck: Deck? {
        if case .deck(let id) = selection {
            return decks.first { $0.persistentModelID == id }
        }
        return nil
    }

    var body: some View {
        // Body-time read so changes to `failure` re-run body and present the alert.
        let failure = persistenceMonitor.failure
        content
            .task {
                // Reflect external edits to the .deck files live; pause while studying.
                watcher.isPaused = studyPlan != nil
                watcher.start { DeckStore.shared.reconcile(into: context) }
            }
            .onChange(of: decks.count) { _, _ in
                // If the selected deck vanished (Delete All Decks, or an external file removal),
                // drop the now-dangling selection so the detail pane falls back to the placeholder.
                if case .deck(let id) = selection, !decks.contains(where: { $0.persistentModelID == id }) {
                    selection = nil
                }
            }
            .onChange(of: studyPlan != nil) { _, studying in
                watcher.isPaused = studying
                if !studying { DeckStore.shared.reconcile(into: context) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // Not while studying: a reconcile can delete cards the live
                    // StudySession still references (the watcher is paused for the same
                    // reason). The study-end handler above reconciles when it finishes.
                    if studyPlan == nil { DeckStore.shared.reconcile(into: context) }
                } else {
                    DeckStore.shared.persist(context)
                }
            }
            .onChange(of: LibraryLocation.shared.current) { _, _ in
                // The library folder changed (in Settings): re-point the watcher and reload.
                watcher.stop()
                watcher.isPaused = studyPlan != nil
                watcher.start { DeckStore.shared.reconcile(into: context) }
                if studyPlan == nil { DeckStore.shared.reconcile(into: context) }
            }
            #if os(macOS)
            .onChange(of: AppActions.shared.showFormattingGuideTick) { _, _ in
                openWindow(id: "formatting-guide")
            }
            #endif
            .alert(
                "Couldn’t Save",
                isPresented: Binding(
                    get: { failure != nil },
                    set: { if !$0 { persistenceMonitor.failure = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        // Study fills the whole window (replaces the split view) rather than a sheet.
        //
        // Do NOT wrap this in `.frame(minWidth:…, minHeight:…)`. A min-frame around a
        // NavigationSplitView breaks its sidebar reveal animation — on expand the column
        // snaps and the toolbar (incl. the search field) re-lays-out mid-animation. The
        // window's minimum size is enforced via `window.minSize` in WindowConfigurator instead.
        Group {
            if let plan = studyPlan {
                // .id ties the session's @State to the plan, so switching plans always
                // starts a fresh session (matches the iOS fullScreenCover(item:) identity).
                StudySessionView(plan: plan, onClose: { studyPlan = nil })
                    .id(plan.id)
            } else {
                splitView
            }
        }
        .background(WindowConfigurator(fullSizeContent: studyPlan != nil))
        #else
        splitView
            .fullScreenCover(item: $studyPlan) { plan in
                StudySessionView(plan: plan, onClose: { studyPlan = nil })
            }
        #endif
    }

    private var splitView: some View {
        NavigationSplitView {
            DeckLibraryView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .today:
            TodayDetailView { studyPlan = $0 }
        case .insights:
            StatsView()
        case .deck:
            if let deck = selectedDeck {
                DeckDetailView(deck: deck) { studyPlan = deckPlan(deck) }
                    .id(deck.persistentModelID)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "Select a Deck",
            systemImage: "rectangle.on.rectangle.angled",
            description: Text("Choose Today or a deck to start studying.")
        )
    }

    private func deckPlan(_ deck: Deck) -> StudyPlan {
        StudyPlan(
            id: "deck-\(deck.id.uuidString)",
            title: deck.name.isEmpty ? "Study" : deck.name,
            accent: Color(hex: deck.colorHex),
            exportText: deck.cardArray.map { "\($0.term) — \($0.definition)" }.joined(separator: "\n"),
            fourButton: deck.gradingMode == .fourButton
        ) {
            let due = deck.dueReviewItems.sorted { $0.dueDate < $1.dueDate }
            return due.isEmpty ? deck.allReviewItems : due
        }
    }
}
