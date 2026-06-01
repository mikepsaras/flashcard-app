import SwiftUI
import SwiftData

/// Full-screen study experience: progress, the flip card, and grading controls.
/// Driven by a `StudyPlan`, so it serves both single decks and the Today queue.
struct StudySessionView: View {
    let plan: StudyPlan

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("trackLearning") private var trackLearning = true
    @AppStorage(GradingMode.storageKey) private var gradingModeRaw = GradingMode.twoButton.rawValue
    @State private var session: StudySession

    init(plan: StudyPlan) {
        self.plan = plan
        let track = UserDefaults.standard.object(forKey: "trackLearning") as? Bool ?? true
        _session = State(initialValue: StudySession(cards: plan.makeCards(), trackLearning: track))
    }

    private var accent: Color { plan.accent }
    private var fourButton: Bool { gradingModeRaw == GradingMode.fourButton.rawValue }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 480
            VStack(spacing: 0) {
                topBar
                if session.isFinished {
                    summary
                } else {
                    studyContent(compact: compact)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Theme.windowBackground)
        }
        .onChange(of: trackLearning) { _, newValue in session.trackLearning = newValue }
        .onDisappear { try? context.save() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            Text(plan.title)
                .font(Typography.headline)
                .lineLimit(1)
            Spacer()
            if let exportText = plan.exportText {
                ShareLink(item: exportText) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.plain)
            }
            Button { finish() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }

    // MARK: Studying

    private func studyContent(compact: Bool) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: 14) {
                ProgressDashBar(answered: session.answered, total: session.total, accent: accent)
                Text("\(session.position) / \(session.total)")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .layoutPriority(1)
                CountBadge(kind: .wrong, count: session.wrongCount)
                CountBadge(kind: .correct, count: session.correctCount)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.s)

            if let card = session.current {
                FlashcardView(
                    term: card.term,
                    definition: card.definition,
                    isShowingDefinition: session.isShowingDefinition,
                    accent: accent,
                    onShuffle: { session.shuffleRemaining() },
                    onTap: { session.flip() }
                )
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.Spacing.m)
            }

            StudyControlsBar(
                canUndo: session.canUndo,
                compact: compact,
                fourButton: fourButton,
                trackLearning: $trackLearning,
                onUndo: { session.undo() },
                onGrade: { session.grade($0) }
            )
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 66))
                .foregroundStyle(accent)
            VStack(spacing: 6) {
                Text("Session Complete")
                    .font(Typography.title)
                Text(session.total == 0 ? "Nothing due — you're all caught up." : "Great work — keep the streak going.")
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
            }
            if session.total > 0 {
                HStack(spacing: 36) {
                    summaryStat("\(session.correctCount)", "Known", Theme.success)
                    summaryStat("\(session.wrongCount)", "To review", Theme.danger)
                }
                .padding(.top, Theme.Spacing.s)
            }
            Spacer()
            VStack(spacing: 12) {
                PrimaryButton(title: "Done", systemImage: "checkmark", tint: accent) { finish() }
                if session.total > 0 {
                    Button("Study Again") { restart() }
                        .buttonStyle(.plain)
                        .font(Typography.headline)
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: 360)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryStat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func finish() {
        try? context.save()
        dismiss()
    }

    private func restart() {
        session = StudySession(cards: plan.makeCards(), trackLearning: trackLearning)
    }
}

extension View {
    /// Presents study full-screen on iOS, as a sized sheet on macOS.
    @ViewBuilder
    func studyCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item) { value in
            content(value).frame(minWidth: 560, idealWidth: 760, minHeight: 600, idealHeight: 720)
        }
        #endif
    }
}
