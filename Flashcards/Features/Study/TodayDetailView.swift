import SwiftUI
import SwiftData

/// Cross-deck review queue: everything due today, with a one-tap study-all.
struct TodayDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    var onStudy: (StudyPlan) -> Void

    private var dueDecks: [(deck: Deck, count: Int)] {
        decks.compactMap { deck in
            let count = deck.dueCount
            return count > 0 ? (deck, count) : nil
        }
    }

    private var totalDue: Int { dueDecks.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if totalDue == 0 {
                ContentUnavailableView(
                    "All Caught Up",
                    systemImage: "checkmark.circle",
                    description: Text("No cards are due right now. Check back later.")
                )
            } else {
                breakdown
            }
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(totalDue)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(totalDue > 0 ? Theme.accent : .secondary)
                    .monospacedDigit()
                Text(totalDue == 1 ? "card due" : "cards due")
                    .font(Typography.title)
                    .foregroundStyle(.secondary)
            }

            PrimaryButton(title: totalDue > 0 ? "Study \(totalDue) Due" : "Nothing Due", systemImage: "play.fill") {
                onStudy(todayPlan())
            }
            .disabled(totalDue == 0)
            .opacity(totalDue == 0 ? 0.5 : 1)
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
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(hex: entry.deck.colorHex))
                            .frame(width: 26, height: 26)
                        Text(entry.deck.name.isEmpty ? "Untitled Deck" : entry.deck.name)
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
            let now = Date.now
            let descriptor = FetchDescriptor<Card>(
                predicate: #Predicate { $0.dueDate <= now },
                sortBy: [SortDescriptor(\.dueDate)]
            )
            return (try? context.fetch(descriptor)) ?? []
        }
    }
}
