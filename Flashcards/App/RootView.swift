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

    // Auto-select Today on macOS; start at the list on iPhone. macOS uses a Set so the sidebar can
    // multi-select decks for deletion; iOS stays single-selection (taps drive navigation).
    #if os(macOS)
    @State private var selection: Set<SidebarItem> = [.today]
    #else
    @State private var selection: SidebarItem?
    #endif

    /// The single selected sidebar item — what the detail pane shows. On macOS it's the lone
    /// selection (nil when zero or several decks are selected).
    private var selectedItem: SidebarItem? {
        #if os(macOS)
        selection.count == 1 ? selection.first : nil
        #else
        selection
        #endif
    }

    private var selectedDeck: Deck? {
        if case .deck(let id) = selectedItem {
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
                // Drop any selected deck that vanished (delete / Delete All / external removal) so the
                // detail pane falls back to the placeholder.
                #if os(macOS)
                selection = selection.filter { item in
                    if case .deck(let id) = item { return decks.contains { $0.persistentModelID == id } }
                    return true
                }
                #else
                if case .deck(let id) = selection, !decks.contains(where: { $0.persistentModelID == id }) {
                    selection = nil
                }
                #endif
            }
            .onChange(of: studyPlan != nil) { _, studying in
                watcher.isPaused = studying
                if !studying { DeckStore.shared.reconcile(into: context) }
            }
            .onChange(of: AppActions.shared.wipeTick) { _, _ in
                // A destructive library action from the Settings window. Deselect any open deck FIRST,
                // then delete — in one transaction, so the detail pane never renders a deleted deck
                // (which traps reading its persisted properties). See AppActions.LibraryWipe.
                guard let wipe = AppActions.shared.pendingWipe else { return }
                AppActions.shared.pendingWipe = nil
                #if os(macOS)
                selection = [.today]
                #else
                selection = .today
                #endif
                switch wipe {
                case .testData:
                    DeveloperTools.removeAllTestData(into: context)
                    context.saveAndPersist()
                case .allDecks:
                    DeckStore.shared.deleteAllDecks(context)
                    StudyStats.reset()
                }
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
        #if os(macOS)
        if selection.count > 1 {
            ContentUnavailableView(
                "\(selection.count) Selected",
                systemImage: "rectangle.stack",
                description: Text("Press Delete to remove the selected decks, or click one to view it.")
            )
        } else {
            detailForSelectedItem
        }
        #else
        detailForSelectedItem
        #endif
    }

    @ViewBuilder
    private var detailForSelectedItem: some View {
        switch selectedItem {
        case .today:
            TodayDetailView { studyPlan = $0 }
        case .insights:
            StatsView(onStudy: { studyPlan = $0 })
        case .deck:
            if let deck = selectedDeck {
                DeckDetailView(deck: deck, onStudy: { studyPlan = deckPlan(deck) }, onCram: { studyPlan = cramPlan(deck) })
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
            onReset: {
                for card in deck.cardArray { card.resetSchedule() }
                context.saveAndPersist(touching: deck)
            }
        ) {
            let dueSorted = deck.dueReviewItems.sorted { $0.dueDate < $1.dueDate }
            let interleaveBy: ((ReviewItem) -> String)? =
                DefaultsKey.interleaveStudyValue() ? { $0.card.section } : nil
            // Genuinely nothing due ⇒ practice over the whole deck, interleaved across sections when
            // the toggle is on (so the setting behaves the same in practice as in a due run — KI-2).
            // Otherwise study the due set with new-card introductions throttled to the daily quota
            // (S0.2). The practice fallback is gated on the *unthrottled* due check, so an exhausted
            // new quota yields an empty (finished) run — never a practice pass that bypasses it.
            if dueSorted.isEmpty {
                let all = deck.allReviewItems
                let ordered = interleaveBy.map { StudySession.interleaved(all, by: $0) } ?? all
                return StudySession.buryingSiblings(ordered)   // keep forward+reverse apart in practice too (S3.4)
            }
            return StudySession.prioritizingReviews(
                dueSorted,
                newPerDay: DefaultsKey.newCardsPerDayValue(),
                introducedToday: StudyStats.newCardsIntroducedToday(),
                interleaveBy: interleaveBy
            )
        }
    }

    /// Adaptive practice / exam-cram over the whole deck: every card, ordered weakest-first by Elo
    /// difficulty (E7), in forced practice mode so the spaced schedule is never touched.
    private func cramPlan(_ deck: Deck) -> StudyPlan {
        StudyPlan(
            id: "cram-\(deck.id.uuidString)",
            title: deck.name.isEmpty ? "Practice" : "\(deck.name) · Practice",
            accent: Color(hex: deck.colorHex),
            exportText: nil,
            forcePractice: true
        ) {
            let ratings = Elo.replay(ReviewLog.records(from: ReviewLog.defaultURL))
            return Elo.adaptiveOrder(deck.allReviewItems, ratings: ratings)
        }
    }
}
