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
    @AppStorage(DefaultsKey.showGradeIntervals) private var showGradeIntervals = false
    @State private var showingResetConfirm = false

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
            .confirmationDialog("Reset progress for this deck?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
                Button("Reset Progress", role: .destructive) { performReset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every card becomes due again and its spaced-repetition history is cleared. This can’t be undone.")
            }
        }
    }

    // MARK: Top bar

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title)
                    .font(Typography.headline)
                    .lineLimit(1)
                if !session.isFinished {
                    Text(sessionSubtitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            if !session.isFinished {
                if currentStreak > 0 { streakChip }
                if !compact { dueChip }   // iPhone keeps only the streak
                overflowMenu
            }
            closeButton
        }
        .padding(.leading, topBarLeadingInset)
        .padding(.trailing, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }

    /// "{position} of {total} · {correct} correct" — session progress, in the title's subtitle.
    private var sessionSubtitle: String {
        "\(session.position) of \(session.total) · \(session.correctCount) correct"
    }

    private var currentStreak: Int { StudyStats.currentStreak() }

    /// Daily streak 🔥 (both platforms). Hidden at 0 so a "🔥 0" never shows.
    private var streakChip: some View {
        Label("\(currentStreak)", systemImage: "flame.fill")
            .font(.system(.caption, design: .rounded, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.orange)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.orange.opacity(Theme.Opacity.fillSubtle), in: Capsule())
            .accessibilityLabel("\(currentStreak) day streak")
    }

    /// Cards left in this run (Mac only; dropped on iPhone to keep the compact bar light).
    private var dueChip: some View {
        let left = max(session.total - session.answered, 0)
        return Label("\(left) due", systemImage: "clock.fill")
            .font(.system(.caption, design: .rounded, weight: .semibold)).monospacedDigit()
            .foregroundStyle(accent)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(accent.opacity(Theme.Opacity.fillSubtle), in: Capsule())
            .accessibilityLabel("\(left) cards left in this session")
    }

    /// Session actions that don't need to be on-screen all the time. Reset Progress only appears for
    /// single-deck runs (the Today queue has no one deck to reset).
    private var overflowMenu: some View {
        Menu {
            Button { session.shuffleAll() } label: { Label("Shuffle", systemImage: "shuffle") }
            if let exportText = plan.exportText {
                ShareLink(item: exportText) { Label("Share Deck", systemImage: "square.and.arrow.up") }
            }
            Button { restart() } label: { Label("Restart Session", systemImage: "arrow.counterclockwise") }
            if plan.onReset != nil {
                Divider()
                Button(role: .destructive) { showingResetConfirm = true } label: {
                    Label("Reset Progress", systemImage: "arrow.uturn.backward.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("More options")
    }

    private var closeButton: some View {
        Button { finish() } label: {
            Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close")
    }

    // MARK: Studying

    private func studyContent(compact: Bool) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            // Dashed progress at the top, right under the title bar — one capsule per card, tinted by
            // the grade it got. (The session count is in the title subtitle; recall lives on the deck page.)
            ProgressDashBar(grades: session.gradeLog, total: session.total)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.xs)

            if session.isPractice { practiceBanner }

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
                // A fixed-ratio card that scales with the window — bigger in full screen, same shape.
                // Compact widths (iPhone) get a tall portrait card; roomy ones (Mac/iPad) a landscape one.
                .aspectRatio(compact ? 0.72 : 1.25, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, compact ? Theme.Spacing.m : Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.s)
            }

            StudyControlsBar(
                canUndo: session.canUndo,
                compact: compact,
                fourButton: fourButton,
                intervalFor: intervalProvider,
                onUndo: { performUndo() },
                onGrade: { performGrade($0) }
            )
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
        }
    }

    /// Shown when nothing's due — a calm reminder that grades won't reschedule. (No track-learning
    /// toggle: due cards always reschedule, which is what spaced repetition is for.)
    @ViewBuilder private var practiceBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
            Text("Practice session — these cards aren't due yet, so your review schedule won't change.")
            Spacer(minLength: 0)
        }
        .font(.system(.caption, design: .rounded, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Practice mode. Nothing is due, so your review schedule won't change.")
    }

    /// Projected next interval per grade for the CURRENT card — a developer diagnostic, returned only
    /// when the hidden toggle is on. Runs SM-2 against the card's per-direction state for each grade.
    private var intervalProvider: ((Grade) -> String)? {
        guard showGradeIntervals, let item = session.current else { return nil }
        let state = item.card.schedulingState(item.direction)
        return { grade in Self.intervalText(SM2.schedule(current: state, grade: grade).interval) }
    }

    private static func intervalText(_ days: Int) -> String {
        if days >= 365 { return "\(days / 365)y" }
        if days >= 30 { return "\(days / 30)mo" }
        return "\(max(days, 1))d"
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
        let wasNew = currentIsNew()
        session.grade(grade)
        // Practice runs (nothing due) don't advance schedules, and must not feed the daily
        // review count / accuracy / streak either — otherwise "Study Again" or studying an
        // already-caught-up deck would keep a streak alive with nothing actually due.
        if !session.isPractice {
            StudyStats.recordReview(correct: grade.isCorrect, mature: wasMature)
            // Count a first-ever review toward today's new-card quota (S0.2 throttle).
            if wasNew { StudyStats.recordNewCardIntroduced() }
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(grade.isCorrect ? .success : .warning)
        #endif
    }

    private func performUndo() {
        guard let undone = session.undo() else { return }
        // Mirror performGrade: only real (non-practice) reviews were recorded, so only those are
        // reversed — and with the same correctness + maturity — keeping the count / accuracy /
        // retention / streak honest. After undo, `session.current` is the restored (pre-grade)
        // item again, so its maturity / newness matches what the grade recorded.
        if !session.isPractice {
            StudyStats.unrecordReview(correct: undone.isCorrect, mature: currentIsMature())
            if currentIsNew() { StudyStats.unrecordNewCardIntroduced() }
        }
    }

    /// Whether `session.current` is a *mature* review unit — its direction's interval is at or past
    /// the mature threshold. Read before grading (and after undo, when the item is restored), so it
    /// reflects the schedule as it stood when the card came up for review.
    private func currentIsMature() -> Bool {
        guard let item = session.current else { return false }
        let interval = item.direction == .forward ? item.card.interval : item.card.reverseInterval
        return interval >= StudyInsights.matureIntervalDays
    }

    /// Whether `session.current` is a *new* unit — its direction has never been reviewed. Read
    /// before grading (and after undo, when the item is restored) to mirror `currentIsMature`.
    private func currentIsNew() -> Bool {
        guard let item = session.current else { return false }
        return item.card.lastReviewedAt(item.direction) == nil
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

    /// Reset Progress (••• menu): wipe the deck's schedules via the plan's hook, then start a fresh
    /// session over the now-all-due cards. Single-deck runs only (the Today queue has no `onReset`).
    private func performReset() {
        plan.onReset?()
        restart()
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
                Button("Shuffle") { session.shuffleAll() }
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
