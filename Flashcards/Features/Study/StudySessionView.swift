import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Full-screen study experience: progress, the flip card, and grading controls.
/// Driven by a `StudyPlan`, so it serves both single decks and the Today queue.
struct StudySessionView: View {
    let plan: StudyPlan
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @AppStorage("trackLearning") private var trackLearning = true
    @AppStorage(GradingMode.storageKey) private var gradingModeRaw = GradingMode.twoButton.rawValue
    @State private var session: StudySession

    init(plan: StudyPlan, onClose: @escaping () -> Void) {
        self.plan = plan
        self.onClose = onClose
        let track = UserDefaults.standard.object(forKey: "trackLearning") as? Bool ?? true
        _session = State(initialValue: StudySession(cards: plan.makeCards(), trackLearning: track))
    }

    private var accent: Color { plan.accent }
    private var fourButton: Bool { gradingModeRaw == GradingMode.fourButton.rawValue }

    /// Extra leading space on macOS so the title clears the overlaid traffic lights
    /// (the window uses a full-size-content title bar during study).
    private var topBarLeadingInset: CGFloat {
        #if os(macOS)
        72
        #else
        Theme.Spacing.m
        #endif
    }

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
            .background(keyboardControls)
        }
        .onChange(of: trackLearning) { _, newValue in session.trackLearning = newValue }
        .onDisappear { try? context.save(); DeckStore.persist(context) }
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
        .padding(.leading, topBarLeadingInset)
        .padding(.trailing, Theme.Spacing.m)
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
                    definitionLabel: card.deck?.backLabel ?? "Definition",
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
                onGrade: { performGrade($0) }
            )
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
        }
    }

    // MARK: Summary

    private var summary: some View {
        let streak = StudyStats.currentStreak()
        return VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 66))
                .foregroundStyle(accent)
            VStack(spacing: 6) {
                Text("Session Complete")
                    .font(Typography.title)
                Text(session.total == 0 ? "Nothing due — you're all caught up." : "Great work — keep it up.")
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
            if streak > 0 {
                Label("\(streak)-day streak", systemImage: "flame.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.orange.opacity(0.14), in: Capsule())
            }
            Spacer()
            VStack(spacing: 12) {
                PrimaryButton(title: "Done", systemImage: "checkmark", tint: accent) { finish() }
                    .keyboardShortcut(.defaultAction)
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

    private func performGrade(_ grade: Grade) {
        session.grade(grade)
        StudyStats.recordReview()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(grade.isCorrect ? .success : .warning)
        #endif
    }

    private func finish() {
        try? context.save()
        DeckStore.persist(context)
        onClose()
    }

    private func restart() {
        session = StudySession(cards: plan.makeCards(), trackLearning: trackLearning)
    }

    // MARK: Keyboard

    /// Hardware-keyboard shortcuts for the study loop (chiefly macOS): Space flips,
    /// ←/→ or 1/2 grade in two-button mode, 1–4 grade in four-button mode, S shuffles,
    /// ⌘Z undoes. Rendered as zero-size hidden buttons so the shortcuts register without
    /// affecting layout.
    @ViewBuilder private var keyboardControls: some View {
        if !session.isFinished {
            Group {
                Button("Flip") { session.flip() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Shuffle") { session.shuffleRemaining() }
                    .keyboardShortcut("s", modifiers: [])
                Button("Undo") { session.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                if fourButton {
                    Button("Again") { performGrade(.again) }.keyboardShortcut("1", modifiers: [])
                    Button("Hard")  { performGrade(.hard) }.keyboardShortcut("2", modifiers: [])
                    Button("Good")  { performGrade(.good) }.keyboardShortcut("3", modifiers: [])
                    Button("Easy")  { performGrade(.easy) }.keyboardShortcut("4", modifiers: [])
                } else {
                    Button("Wrong") { performGrade(.again) }.keyboardShortcut(.leftArrow, modifiers: [])
                    Button("Right") { performGrade(.good) }.keyboardShortcut(.rightArrow, modifiers: [])
                    Button("Wrong 1") { performGrade(.again) }.keyboardShortcut("1", modifiers: [])
                    Button("Right 2") { performGrade(.good) }.keyboardShortcut("2", modifiers: [])
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}
