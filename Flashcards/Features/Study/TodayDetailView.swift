import SwiftUI
import SwiftData

/// Cross-deck review queue: everything due today, with a one-tap study-all.
struct TodayDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @AppStorage(StudyStats.revisionKey) private var statsRevision = 0
    var onStudy: (StudyPlan) -> Void

    private var dueDecks: [(deck: Deck, count: Int)] {
        decks.compactMap { deck in
            let count = deck.dueCount
            return count > 0 ? (deck, count) : nil
        }
    }

    private var totalDue: Int { dueDecks.reduce(0) { $0 + $1.count } }

    var body: some View {
        let _ = statsRevision   // re-render when stats are reset (the log isn't otherwise observed)
        Group {
            if totalDue == 0 {
                let streak = StudyStats.currentStreak()
                ContentUnavailableView(
                    "All Caught Up",
                    systemImage: "checkmark.circle",
                    description: Text(streak > 0
                        ? "No cards are due right now. You’re on a \(streak)-day streak — check back later."
                        : "No cards are due right now. Check back later.")
                )
            } else {
                VStack(spacing: 0) {
                    header
                    #if os(macOS)
                    Divider()   // separates the header band from the list (same bg color on macOS)
                    #endif
                    breakdown
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.groupedBackground)
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        let streak = StudyStats.currentStreak()
        let planned = plannedItems().count
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(totalDue)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
                Text(totalDue == 1 ? "card due" : "cards due")
                    .font(Typography.title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if streak > 0 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                        .help("\(streak)-day study streak")
                        .accessibilityLabel("\(streak)-day study streak")
                }
            }

            PrimaryButton(title: planned == totalDue ? "Study \(totalDue) Due" : "Study \(planned) Now",
                          systemImage: "play.fill") {
                onStudy(todayPlan())
            }
            if planned < totalDue {
                Text("New cards are introduced gradually, so this session studies \(planned) of the \(totalDue) due.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.windowBackground)
    }

    private var breakdown: some View {
        List {
            Section("Due by deck") {
                ForEach(dueDecks, id: \.deck.persistentModelID) { entry in
                    HStack(spacing: 12) {
                        DeckIconChip(icon: entry.deck.icon, colorHex: entry.deck.colorHex, size: 26)
                        Text(entry.deck.displayName)
                            .font(Typography.body)
                        Spacer()
                        Text("\(entry.count)")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private func todayPlan() -> StudyPlan {
        StudyPlan(id: "today", title: "Today", accent: Theme.accent, exportText: nil) {
            // Cross-deck due units, including reverse where enabled. Built in memory so
            // reverse due dates (a #Predicate can't reach through the relationship) count.
            let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
            let due = decks.flatMap { $0.dueReviewItems }.sorted { $0.dueDate < $1.dueDate }
            // Reviews first, then new throttled to the day's remaining quota (S0.2); optionally
            // interleaved across decks so one deck's cards don't cluster (S0.3).
            return StudySession.prioritizingReviews(
                due,
                newPerDay: DefaultsKey.newCardsPerDayValue(),
                introducedToday: StudyStats.newCardsIntroducedToday(),
                interleaveBy: DefaultsKey.interleaveStudyValue() ? { $0.card.deck?.id.uuidString ?? "" } : nil
            )
        }
    }

    /// The cards this Today session will ACTUALLY present — due reviews plus new cards throttled to the
    /// daily quota, then the session-size cap — so the button's count matches the session, not the raw
    /// due total (which counts every new card). Mirrors `todayPlan`'s composition.
    private func plannedItems() -> [ReviewItem] {
        let due = decks.flatMap { $0.dueReviewItems }.sorted { $0.dueDate < $1.dueDate }
        let prioritized = StudySession.prioritizingReviews(
            due,
            newPerDay: DefaultsKey.newCardsPerDayValue(),
            introducedToday: StudyStats.newCardsIntroducedToday()
        )
        return StudySession.cap(prioritized, limit: UserDefaults.standard.integer(forKey: DefaultsKey.studySessionLimit))
    }
}
