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
    /// Ids of review-log records written this run, so undo can void the right one (S1.3).
    @State private var loggedRecordIDs: [UUID] = []
    /// Type-in answer (B3), reset per card: the learner's typed text and whether it matched. A nil
    /// result means "not checked" (e.g. the card was revealed by tapping instead of typing).
    @State private var typedAnswer = ""
    @State private var typedResult: Bool? = nil
    @FocusState private var answerFieldFocused: Bool

    init(plan: StudyPlan, onClose: @escaping () -> Void) {
        self.plan = plan
        self.onClose = onClose
        // Grading always advances the spaced-repetition schedule for due cards; the engine still
        // skips rescheduling in Practice mode (nothing due), so caught-up review is safe.
        _session = State(initialValue: StudySession(items: Self.cappedItems(plan.makeItems()), trackLearning: true, forcePractice: plan.forcePractice))
    }

    private var accent: Color { plan.accent }

    /// This card is answered by typing — its resolved answer mode is `type`. Resolved per card from
    /// its own deck's default, so the cross-deck Today queue honors each card as it crosses decks.
    private var typeInCard: Bool {
        guard let card = session.current?.card else { return false }
        return card.resolvedAnswerMode(deckDefault: card.deck?.defaultAnswerMode ?? .flip) == .type
    }

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
            // Clear the typed answer when the card changes (advance / undo / shuffle) so the next
            // type-in card starts blank.
            .onChange(of: session.current?.id) { _, _ in
                typedAnswer = ""
                typedResult = nil
            }
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
            closeButton   // top-left, matching the gallery editor
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
                    showFlipHint: !typeInCard,
                    onTap: { session.flip() }
                )
                // A fixed-ratio card that scales with the window — bigger in full screen, same shape.
                // Compact widths (iPhone) get a tall portrait card; roomy ones (Mac/iPad) a landscape one.
                .aspectRatio(compact ? 0.72 : 1.25, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, compact ? Theme.Spacing.m : Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.s)

                // The card's elaboration ("why"), revealed under the card once flipped to the answer (B1).
                if session.isShowingDefinition, !item.extra.isEmpty {
                    ElaborationPanel(text: item.extra, accent: accent, compact: compact)
                        .padding(.horizontal, compact ? Theme.Spacing.m : Theme.Spacing.xl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Type-in answer (B3): a text field before the reveal, a ✓/✗ result after.
            if typeInCard, let item = session.current {
                typeAnswerArea(item: item)
                    .padding(.horizontal, compact ? Theme.Spacing.m : Theme.Spacing.xl)
            }

            // Type-in cards infer the grade from the typed answer (✓ → Good, ✗ → Again), so they get
            // a Continue bar instead of the Know / grade pills; flip-mode cards keep the pills.
            Group {
                if typeInCard {
                    typeInControls
                } else {
                    StudyControlsBar(
                        canUndo: session.canUndo,
                        compact: compact,
                        intervalFor: intervalProvider,
                        onUndo: { performUndo() },
                        onGrade: { performGrade($0) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
        }
        // Springs the elaboration panel in/out as the card flips.
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: session.isShowingDefinition)
    }

    // MARK: Type-in answer (B3)

    /// Beneath the card on a type-in card: a text field before the reveal, then a ✓/✗ result row once
    /// the answer's been checked. (Revealing by tapping the card instead of typing shows no row.)
    @ViewBuilder private func typeAnswerArea(item: ReviewItem) -> some View {
        if session.isShowingDefinition {
            if let typedResult { typeResultRow(matched: typedResult) }
        } else {
            typeAnswerField
        }
    }

    private var canCheck: Bool { !typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var typeAnswerField: some View {
        HStack(spacing: 10) {
            TextField("Type the answer…", text: $typedAnswer)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Theme.cardSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
                .focused($answerFieldFocused)
                .submitLabel(.done)
                .onSubmit(submitTypedAnswer)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif
            Button(action: submitTypedAnswer) {
                Text("Check")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(accent, in: Capsule())
                    .opacity(canCheck ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!canCheck)
        }
        // Focus the field whenever it (re)appears for a new type-in card.
        .onAppear { answerFieldFocused = true }
    }

    @ViewBuilder private func typeResultRow(matched: Bool) -> some View {
        let tint = matched ? Theme.success : Theme.danger
        HStack(spacing: 8) {
            Image(systemName: matched ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(tint)
            if matched {
                Text("Correct")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(tint)
            } else {
                (Text("You typed ").foregroundStyle(.secondary)
                    + Text("“\(typedAnswer)”").foregroundStyle(.primary).fontWeight(.semibold))
                    .font(.system(.subheadline, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(matched ? "Correct" : "Incorrect. You typed \(typedAnswer)")
    }

    /// Checks the typed answer against the card's answer (case-insensitively) and reveals it. The
    /// grade is then inferred from the match (see `typeInControls`); the learner can still override.
    private func submitTypedAnswer() {
        guard let item = session.current, !session.isShowingDefinition, canCheck else { return }
        typedResult = AnswerCheck.matches(typedAnswer, item.back)
        answerFieldFocused = false
        session.flip()
    }

    /// Bottom controls for a type-in card. Before the reveal: just Undo. After a *correct* answer:
    /// Good / Easy pills (Good is the Enter default) — the objective pass floor; the learner refines
    /// only the upside. After a *wrong* answer: Continue (Again) with an "I actually knew it" escape
    /// hatch for typos.
    @ViewBuilder private var typeInControls: some View {
        let correct = typedResult ?? false
        VStack(spacing: 12) {
            HStack {
                undoButton
                Spacer()
                // Typo escape hatch: it was marked wrong, but you actually knew it ⇒ count as Good.
                if session.isShowingDefinition && !correct {
                    Button { performGrade(.good) } label: {
                        Text("I actually knew it")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Counts this as known")
                }
            }
            if session.isShowingDefinition {
                if correct {
                    HStack(spacing: 10) {
                        refineButton("Good", .good, primary: true)
                            .keyboardShortcut(.return, modifiers: [])
                        refineButton("Easy", .easy)
                    }
                } else {
                    Button { performGrade(.again) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Continue")
                        }
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }

    /// One pill in the type-in "you got it — how well?" refinement. `primary` (Good) gets a solid fill
    /// so it reads as the default; Easy is tinted, matching the grade pills.
    private func refineButton(_ title: String, _ grade: Grade, primary: Bool = false) -> some View {
        let color = grade.studyColor
        let fill: Color = primary ? color : color.opacity(Theme.Opacity.fillTint)
        return Button { performGrade(grade) } label: {
            Text(title)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(primary ? Color.white : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(fill, in: Capsule())
                .overlay { if !primary { Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    /// The small Undo control reused by the type-in bar (the grade-pill bar has its own).
    private var undoButton: some View {
        Button { performUndo() } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .buttonStyle(.plain)
        .foregroundStyle(session.canUndo ? Color.secondary : Color.secondary.opacity(0.4))
        .disabled(!session.canUndo)
        .accessibilityLabel("Undo")
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
    /// when the hidden toggle is on. Runs the deck's scheduler against the card's per-direction state.
    private var intervalProvider: ((Grade) -> String)? {
        guard showGradeIntervals, let item = session.current else { return nil }
        let state = item.card.schedulingState(item.direction)
        let scheduler = item.card.deck?.resolvedScheduler ?? FSRSScheduler()
        return { grade in Self.intervalText(scheduler.schedule(current: state, grade: grade).interval) }
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
        let pending = pendingReviewRecord(grade: grade)   // from the pre-grade schedule
        session.grade(grade)
        // Practice runs (nothing due) don't advance schedules, and must not feed the daily review
        // count / accuracy / streak / review log either — otherwise "Study Again" or studying an
        // already-caught-up deck would keep a streak alive with nothing actually due.
        if !session.isPractice {
            StudyStats.recordReview(correct: grade.isCorrect, mature: wasMature)
            // Count a first-ever review toward today's new-card quota (S0.2 throttle).
            if wasNew { StudyStats.recordNewCardIntroduced() }
            // Append to the per-review history (S1.3); remember the id so undo can void it.
            if let pending {
                ReviewLog.append(pending, to: ReviewLog.defaultURL)
                loggedRecordIDs.append(pending.id)
            }
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
            // Void the matching log record (append-only; no rewrite). The stack stays aligned with
            // the grade history since a session is entirely practice or entirely not.
            if let id = loggedRecordIDs.popLast() {
                ReviewLog.void(id, to: ReviewLog.defaultURL)
            }
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

    /// A review-log record for `session.current` built from its PRE-grade schedule (call before
    /// `session.grade`). nil when there's no current item or it has no deck.
    private func pendingReviewRecord(grade: Grade, now: Date = .now) -> ReviewLog.Record? {
        guard let item = session.current, let deckID = item.card.deck?.id else { return nil }
        let direction = item.direction
        let interval = direction == .forward ? item.card.interval : item.card.reverseInterval
        let elapsed = item.card.lastReviewedAt(direction)
            .map { max(now.timeIntervalSince($0) / 86_400, 0) } ?? 0
        return ReviewLog.Record(
            ts: now, deck: deckID, card: item.card.id, direction: direction,
            grade: grade.rawValue, correct: grade.isCorrect,
            elapsedDays: elapsed, intervalBefore: interval,
            mature: interval >= StudyInsights.matureIntervalDays
        )
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
        session = StudySession(items: Self.cappedItems(plan.makeItems()), trackLearning: true, forcePractice: plan.forcePractice)
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
    /// 1/2/3 → Again/Good/Easy (← Again, → Good), S shuffles, ⌘Z undoes. Rendered as
    /// zero-size hidden buttons so the shortcuts register without affecting layout.
    @ViewBuilder private var keyboardControls: some View {
        // Suppressed for type-in cards (B3): before the reveal so Space / S / 1–3 / arrows type into
        // the field, and after it because the grade is inferred via Continue (Return) — the flip-mode
        // shortcuts would otherwise grade or flip the answer back.
        if !session.isFinished && !typeInCard {
            Group {
                Button("Flip") { session.flip() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Shuffle") { session.shuffleAll() }
                    .keyboardShortcut("s", modifiers: [])
                Button("Undo") { performUndo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Again") { performGrade(.again) }.keyboardShortcut("1", modifiers: [])
                Button("Good")  { performGrade(.good) }.keyboardShortcut("2", modifiers: [])
                Button("Easy")  { performGrade(.easy) }.keyboardShortcut("3", modifiers: [])
                Button("Again ←") { performGrade(.again) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Good →")  { performGrade(.good) }.keyboardShortcut(.rightArrow, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}
