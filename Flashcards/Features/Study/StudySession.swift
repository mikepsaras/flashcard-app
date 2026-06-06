import SwiftUI

/// Drives a single study run: a queue of review items (cards in a direction), a current
/// position, flip state, running ✓/✕ tallies, and an exact undo stack. SM-2 grades are
/// applied to each item's direction only when `trackLearning` is on. A miss in a real
/// (tracked, non-practice) run re-inserts the card later in the same queue for one more
/// look — a lightweight learning step — so the queue can grow during the run.
@Observable
@MainActor
final class StudySession {
    private(set) var items: [ReviewItem]
    private(set) var index = 0
    private(set) var isShowingDefinition = false
    private(set) var correctCount = 0
    private(set) var wrongCount = 0
    /// The grade given to each answered card, in order — used to color the progress bar.
    private(set) var gradeLog: [Grade] = []
    var trackLearning: Bool
    /// A run where nothing is actually due — a pure practice pass (e.g. "Study Again" after
    /// the deck's due cards are cleared, or studying a deck ahead of schedule). Schedules are
    /// never advanced in practice, so repeating it can't inflate intervals; the ✓/✕ scoreboard
    /// still works.
    let isPractice: Bool

    /// Snapshot captured before each grade so undo can restore exactly.
    private struct Move {
        let item: ReviewItem
        let wasShowingDefinition: Bool
        let previousState: SchedulingState
        let previousReviewedAt: Date?
        let previousModifiedAt: Date
        let previousIndex: Int
        let previousCorrect: Int
        let previousWrong: Int
        /// The card's whole-card lapse count before this grade, restored on undo (S7.4).
        let previousLapses: Int
        /// The item's requeue count before this grade, restored on undo.
        let previousRequeueCount: Int
        /// Index where a copy was re-inserted for another look this session, or nil if the grade
        /// didn't requeue. Removed on undo (LIFO keeps this index valid).
        let requeuedAt: Int?
    }
    private var history: [Move] = []

    /// How many cards ahead a missed card is re-inserted for another look this session — a
    /// lightweight learning step, so a miss isn't gone until tomorrow but doesn't reappear
    /// instantly either.
    private static let requeueSpacing = 3
    /// A missed card keeps returning for another look until it's passed — up to this many requeues
    /// per card, so a card you genuinely can't get can't grow the run without bound (it's still
    /// rescheduled for a future day either way).
    private static let maxRequeuesPerItem = 3
    /// Re-show count per item id this session, enforcing `maxRequeuesPerItem` and kept honest
    /// across undo.
    private var requeueCounts: [String: Int] = [:]

    init(items: [ReviewItem], trackLearning: Bool, forcePractice: Bool = false, now: Date = .now) {
        self.items = items
        self.trackLearning = trackLearning
        // Nothing due ⇒ practice. Studying cards that aren't due (and advancing them) would
        // push their intervals out further with every pass, so practice leaves them alone.
        // `forcePractice` (adaptive cram) forces it regardless of due status, so drilling can't
        // corrupt the spaced schedule.
        self.isPractice = forcePractice || (!items.isEmpty && items.allSatisfy { !$0.card.isDue($0.direction, now: now) })
    }

    /// Convenience: a forward-only run (used by tests and single-direction callers).
    convenience init(cards: [Card], trackLearning: Bool) {
        self.init(items: cards.map { ReviewItem(card: $0, direction: .forward) }, trackLearning: trackLearning)
    }

    /// Applies the "cards per session" cap to a list of review items (0 ⇒ unlimited),
    /// taking the leading `limit` (callers pass them most-due first). Pure and static so
    /// it's unit-testable without the view's `@AppStorage`.
    static func cap(_ items: [ReviewItem], limit: Int) -> [ReviewItem] {
        limit > 0 ? Array(items.prefix(limit)) : items
    }

    /// Orders a due set so reviews always come before new cards, and throttles how many *new*
    /// units (never reviewed in their direction) are introduced: every due review is kept, then
    /// up to `newPerDay - introducedToday` new units (`newPerDay <= 0` ⇒ unlimited new). Callers
    /// pass the set most-due first; reviews and new each keep that order. Putting reviews first
    /// means new cards never crowd out due reviews under the session cap (new cards sort early,
    /// since an unreviewed card's due date is its creation date). Pure + static ⇒ unit-testable.
    static func prioritizingReviews(
        _ items: [ReviewItem],
        newPerDay: Int,
        introducedToday: Int,
        interleaveBy keyFn: ((ReviewItem) -> String)? = nil
    ) -> [ReviewItem] {
        var reviews: [ReviewItem] = []
        var newUnits: [ReviewItem] = []
        for item in items {
            if item.card.lastReviewedAt(item.direction) == nil { newUnits.append(item) }
            else { reviews.append(item) }
        }
        let allowedNew = newPerDay > 0 ? max(0, newPerDay - introducedToday) : newUnits.count
        let cappedNew = Array(newUnits.prefix(allowedNew))
        // Interleave each segment independently so reviews still precede new (S0.2) while related
        // cards within each are spread apart (S0.3). No key ⇒ keep the incoming due order.
        guard let keyFn else { return reviews + cappedNew }
        return interleaved(reviews, by: keyFn) + interleaved(cappedNew, by: keyFn)
    }

    /// Round-robins items across groups keyed by `keyFn`, preserving each group's internal order, so
    /// related cards (same deck, or same section) are spread out rather than clustered — an
    /// interleaving "desirable difficulty". Groups are visited in first-appearance order, so the
    /// most-overdue group still leads. Pure + static ⇒ unit-testable.
    static func interleaved(_ items: [ReviewItem], by keyFn: (ReviewItem) -> String) -> [ReviewItem] {
        var groups: [[ReviewItem]] = []
        var indexByKey: [String: Int] = [:]
        for item in items {
            let k = keyFn(item)
            if let i = indexByKey[k] { groups[i].append(item) }
            else { indexByKey[k] = groups.count; groups.append([item]) }
        }
        var out: [ReviewItem] = []
        out.reserveCapacity(items.count)
        var offset = 0, added = true
        while added {
            added = false
            for group in groups where offset < group.count {
                out.append(group[offset]); added = true
            }
            offset += 1
        }
        return out
    }

    // MARK: Derived state
    var total: Int { items.count }
    var answered: Int { index }
    var position: Int { min(index + 1, max(total, 1)) }
    var isFinished: Bool { index >= items.count }
    var current: ReviewItem? { isFinished ? nil : items[index] }
    var canUndo: Bool { !history.isEmpty }

    // MARK: Intents

    func flip() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            isShowingDefinition.toggle()
        }
    }

    /// Two-button convenience: ✓ ⇒ good, ✕ ⇒ again.
    func grade(known: Bool, now: Date = .now) {
        grade(.from(known: known), now: now)
    }

    /// Grade the current item with an explicit SM-2 grade (used by 4-button mode).
    func grade(_ grade: Grade, now: Date = .now) {
        guard let item = current else { return }
        let card = item.card
        let direction = item.direction

        // A miss in a real (tracked, non-practice) run earns one more look later this session — a
        // minimal learning step so the card isn't gone until tomorrow. Bounded per item so a
        // chronic miss can't balloon the run. Computed against the pre-insert queue/index.
        let willRequeue = trackLearning && !isPractice && !grade.isCorrect
            && (requeueCounts[item.id] ?? 0) < Self.maxRequeuesPerItem
        let requeuedAt = willRequeue ? min(index + 1 + Self.requeueSpacing, items.count) : nil

        history.append(Move(
            item: item,
            wasShowingDefinition: isShowingDefinition,
            previousState: card.schedulingState(direction),
            previousReviewedAt: card.lastReviewedAt(direction),
            previousModifiedAt: card.modifiedAt,
            previousIndex: index,
            previousCorrect: correctCount,
            previousWrong: wrongCount,
            previousLapses: card.lapses,
            previousRequeueCount: requeueCounts[item.id] ?? 0,
            requeuedAt: requeuedAt
        ))

        if trackLearning && !isPractice {
            // Resolve the scheduler per item from its deck, so a cross-deck Today queue advances each
            // card with its own deck's algorithm (SM-2 or FSRS).
            let scheduler = card.deck?.resolvedScheduler ?? SM2Scheduler()
            let updated = scheduler.schedule(current: card.schedulingState(direction), grade: grade, now: now)
            card.apply(updated, direction: direction, reviewedAt: now)
            // A failed recall (Again) is a lapse — bump the whole-card counter so cards you keep
            // failing surface as leeches (S7.4). Gated exactly like rescheduling above (real, tracked,
            // non-practice run), counted once per failed grade, and reversed by undo's snapshot.
            if !grade.isCorrect { card.lapses += 1 }
            // Mark the deck modified so the (saveAndPersist-bypassing) study persist re-writes it:
            // `DeckStore` skips encoding decks whose `modifiedAt` is unchanged, and apply() only bumps
            // the *card's* modifiedAt.
            card.deck?.modifiedAt = now
        }

        if grade.isCorrect { correctCount += 1 } else { wrongCount += 1 }
        gradeLog.append(grade)

        if let requeuedAt {
            items.insert(item, at: requeuedAt)
            requeueCounts[item.id, default: 0] += 1
        }
        advance()
    }

    @discardableResult
    func undo() -> Grade? {
        guard let move = history.popLast() else { return nil }
        let undoneGrade = gradeLog.popLast()

        // Undo any learning-step requeue this grade added. Undo is strictly LIFO, so every later
        // move has already been undone and `items` is back to the exact state right after this
        // grade ran — `requeuedAt` is still the copy's index.
        if let at = move.requeuedAt, at < items.count {
            items.remove(at: at)
            requeueCounts[move.item.id] = move.previousRequeueCount
        }

        // Always restore the snapshot — never gate this on the *current* `trackLearning`
        // value. If the grade applied an SM-2 change, this reverts it; if it didn't (tracking
        // was off at grade time), restoring the captured state is a no-op. Reading the live
        // flag instead would leave a card advanced when tracking is toggled off after grading.
        move.item.card.restore(
            move.previousState,
            direction: move.item.direction,
            lastReviewedAt: move.previousReviewedAt,
            modifiedAt: move.previousModifiedAt
        )
        // Reverse any lapse this grade counted (S7.4). Restored unconditionally to the captured value
        // for the same reason the schedule is — never gate on the live `trackLearning` flag.
        move.item.card.lapses = move.previousLapses

        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            index = move.previousIndex
            correctCount = move.previousCorrect
            wrongCount = move.previousWrong
            isShowingDefinition = move.wasShowingDefinition
        }
        return undoneGrade
    }

    /// Shuffles the entire run and restarts it from the top — "shuffle the deck" — the same in both
    /// practice and real study runs. Progress (position, ✓/✕ tallies, grade log) and the undo history
    /// reset, since the whole order changes. A practice run never touched schedules; a real run simply
    /// re-reviews its cards in the new order.
    func shuffleAll() {
        guard !items.isEmpty else { return }
        history.removeAll()
        requeueCounts.removeAll()
        // Drop any in-session learning-step duplicates so a restart is a clean pass over the
        // unique set rather than carrying this pass's requeued copies forward.
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            items = unique.shuffled()
            index = 0
            correctCount = 0
            wrongCount = 0
            gradeLog.removeAll()
            isShowingDefinition = false
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            isShowingDefinition = false
            index += 1
        }
    }
}
