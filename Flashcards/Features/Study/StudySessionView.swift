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
    @State private var session: StudySession

    init(plan: StudyPlan, onClose: @escaping () -> Void) {
        self.plan = plan
        self.onClose = onClose
        // Grading always advances the spaced-repetition schedule for due cards; the engine still
        // skips rescheduling in Practice mode (nothing due), so caught-up review is safe.
        _session = State(initialValue: StudySession(items: Self.cappedItems(plan.makeItems()), trackLearning: true))
    }

    private var accent: Color { plan.accent }
    private var fourButton: Bool { plan.fourButton }

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
                topBar(compact: compact)
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
    }

    // MARK: Top bar

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 14) {
            Text(plan.title)
                .font(Typography.headline)
                .lineLimit(1)
            Spacer()
            // Session controls live here now (off the card / bottom bar), only while studying.
            if !session.isFinished {
                Button { session.shuffleRemaining() } label: { Image(systemName: "shuffle") }
                    .buttonStyle(.plain)
                    .help("Shuffle remaining cards")
                    .accessibilityLabel("Shuffle remaining cards")
                practiceBadge(compact: compact)
            }
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

    /// A quiet "Practice" badge shown when nothing's due — grades won't change the schedule. (There's
    /// no track-learning toggle: due cards always reschedule, which is what spaced repetition is for.)
    @ViewBuilder private func practiceBadge(compact: Bool) -> some View {
        if session.isPractice {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill").font(.system(size: 12))
                if !compact { Text("Practice").font(.system(size: 12, weight: .medium, design: .rounded)) }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .help("Practice mode — nothing is due, so your review schedule won't change")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Practice mode")
            .accessibilityHint("Nothing is due, so your review schedule won't change")
        }
    }

    // MARK: Studying

    private func studyContent(compact: Bool) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: 14) {
                ProgressDashBar(colors: session.gradeLog.map(\.studyColor), total: session.total)
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

            if let item = session.current {
                FlashcardView(
                    term: item.front,
                    definition: item.back,
                    isShowingDefinition: session.isShowingDefinition,
                    definitionLabel: item.backLabel ?? "",
                    section: item.section,
                    accent: accent,
                    onTap: { session.flip() }
                )
                // A fixed-ratio card that scales with the window — bigger in full screen, same shape —
                // centered in the available space with a margin so it never touches the edges.
                .aspectRatio(1.25, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.s)
            }

            StudyControlsBar(
                canUndo: session.canUndo,
                compact: compact,
                fourButton: fourButton,
                onUndo: { performUndo() },
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
        // Capture maturity from the *pre-grade* schedule (before grade() advances the card) so the
        // "true retention" tally buckets by the card's maturity at review time, Anki-style.
        let wasMature = currentIsMature()
        session.grade(grade)
        // Practice runs (nothing due) don't advance schedules, and must not feed the daily
        // review count / accuracy / streak either — otherwise "Study Again" or studying an
        // already-caught-up deck would keep a streak alive with nothing actually due.
        if !session.isPractice { StudyStats.recordReview(correct: grade.isCorrect, mature: wasMature) }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(grade.isCorrect ? .success : .warning)
        #endif
    }

    private func performUndo() {
        guard let undone = session.undo() else { return }
        // Mirror performGrade: only real (non-practice) reviews were recorded, so only those are
        // reversed — and with the same correctness + maturity — keeping the count / accuracy /
        // retention / streak honest. After undo, `session.current` is the restored (pre-grade)
        // item again, so its maturity matches what `recordReview` saw.
        if !session.isPractice { StudyStats.unrecordReview(correct: undone.isCorrect, mature: currentIsMature()) }
    }

    /// Whether `session.current` is a *mature* review unit — its direction's interval is at or past
    /// the mature threshold. Read before grading (and after undo, when the item is restored), so it
    /// reflects the schedule as it stood when the card came up for review.
    private func currentIsMature() -> Bool {
        guard let item = session.current else { return false }
        let interval = item.direction == .forward ? item.card.interval : item.card.reverseInterval
        return interval >= StudyInsights.matureIntervalDays
    }

    private func finish() {
        // The single persist on study exit. It must run BEFORE onClose() clears the plan:
        // clearing it triggers RootView's post-study reconcile, which reads these files back,
        // so they have to be current first. (No onDisappear persist — finish, or a scene-
        // background while studying, always covers it, without rewriting every deck twice.)
        try? context.save()
        DeckStore.shared.persist(context)
        onClose()
    }

    private func restart() {
        session = StudySession(items: Self.cappedItems(plan.makeItems()), trackLearning: true)
    }

    /// Applies the "cards per session" setting (0 ⇒ unlimited). The cap logic lives on
    /// `StudySession` (unit-tested); this just supplies the stored limit.
    private static func cappedItems(_ items: [ReviewItem]) -> [ReviewItem] {
        StudySession.cap(items, limit: UserDefaults.standard.integer(forKey: DefaultsKey.studySessionLimit))
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
                Button("Undo") { performUndo() }
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
