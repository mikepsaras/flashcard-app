# Flashcards — Learning-Efficacy Backlog

The plan for closing the gap between "a clean SM-2 flashcard app" and "a tool that
genuinely builds durable, applicable subject-matter knowledge." Derived from a
technical audit of the study engine, scheduler, retention math, data model, and AI
generation. This file is the **execution source of truth** — keep it current as work
lands (multiple agents/sessions edit this repo; see `CLAUDE.md`).

## How to read this

- Work is grouped into **epics (E0–E7)**, each a cluster of **stories (S…)**.
- The 13 audited gaps are **not** 13 independent tasks — they collapse onto **three
  enablers** plus a handful of no-migration quick wins. Sequence by dependency, not by
  gap number.
- Each story lists: **Why**, **Touches** (code seams), **Model/persist** impact,
  **Acceptance**, **Deps**, **Effort**, **Phase**.

**Status:** ☐ not started · ◐ in progress · ☑ done · ✖ dropped
**Effort:** S ≤1d · M 2–4d · L ~1wk · XL 2wk+
**Phase:** 0 (ship now, no migration) · 1 (foundations / format v3) · 2 (features on
foundations) · 3 (ambitious / optional)

---

## Decision log (resolved forks)

1. **Scheduler: adopt FSRS, retire SM-2 as the default.** FSRS subsumes four gaps at
   once (learning steps, lapse handling, grading-signal, algorithm efficiency). SM-2
   stays as a selectable conformer for back-compat and A/B.
2. **Cloze first via interim `type` enum on `Card`**, expanded into multiple
   `ReviewItem`s (reusing the forward/reverse expansion pattern). The full `Note`-above-
   `Card` refactor is deferred to Phase 3 once cloze demand is validated.
3. **Elo is in scope, scoped deliberately:** it powers the **adaptive practice/exam-cram
   mode** (its one non-redundant, load-bearing use) **and** is surfaced as a **difficulty
   / per-topic mastery metric**. It does **not** drive the spaced schedule (FSRS owns
   that). Leech detection rides primarily on a simple lapse counter, with difficulty as
   corroboration.
4. **Review history: an append-only sidecar log** (`reviewlog.jsonl` in the Flashcards
   folder), not per-review records inside `.cards` files — keeps deck files human-
   readable. Enables honest metrics, FSRS optimization, Elo history, and calibration.
5. **Batch all model changes into one format bump (v2 → v3).** Every new scalar stays
   defaulted (CloudKit-safe); migration seeds, never resets.
6. **FSRS source & target retention.** Port from a permissively-licensed FSRS reference
   (e.g. `rs-fsrs` / `ts-fsrs`), latest stable (v5/v6 family) with **published default
   weights — no training required**. Default **desired retention 0.90**, surfaced as a
   setting later.
7. **Default grading under FSRS = 2-button (Know / Don't-know).** FSRS reads binary
   outcomes well (it doesn't rely on SM-2's ease asymmetry that made 2-button lossy), so
   the low-friction default is no longer a real handicap; **4-button stays available per
   deck** for Hard/Easy nuance.
8. **Cloze scheduling = whole-card for v1.** One schedule per cloze card initially;
   per-cloze-index independent scheduling is deferred to the `Note` refactor (S3.5),
   tracked as a TODO in S3.2.
9. **~~Topic unit = tags~~ → Subject/Deck/Section.** Reversed after review: the existing **Subject → Deck → Section** hierarchy covers coverage, mastery, and per-topic Elo. Tags (the dormant `Card.tags` field) were **deleted**; revisit only if cross-cutting/cross-deck concepts become a real need.
   computed per **tag** (cross-deck, many-to-many — the right grain for "expertise in X");
   deck `section` stays a secondary grouping.
10. **Elo confidence = Glicko-style (rating + deviation).** Track a deviation so new
    cards/topics read e.g. `1500 ± 350`, not false precision — it's surfaced as a mastery
    metric. Marginal extra code over plain decaying-K.
11. **Leech = ≥8 lapses (default), actionable.** Needs the `lapses` counter (S7.4);
    actions = suspend / reset / edit / tag. Lapse count is the primary signal; difficulty
    only corroborates.
12. **Interim `type` enum first; `Note` refactor deferred.** Reaffirms #2 — ship
    cloze/type-in on a `Card.type` enum (S3.1–S3.3, format v3) in Phase 2; commit to the
    full `Note`-above-`Card` model (S3.5, format v4) only once demand is proven.
13. **Review log = one global `reviewlog.jsonl` in Application Support.** A single
    chronological append-only stream in the app's private Application Support folder — **not**
    the visible deck folder (keeps it clean) — each record carrying `deck` / `card` /
    `direction` so per-deck/per-tag slicing still works. Device-local; a launch migration
    relocates any log an earlier build left in the library folder. _(Revised from "library
    folder" after hand-testing flagged the clutter.)_

---

## 1.8.0 — Editor & Answer-Mode rework (clean break, in progress)

A ground-up rework of card answer modes + a new graphical editor, shipping as **1.8.0**
(build 19). **Clean break: old `.cards` files are NOT supported** — supersedes the additive
"format v3 / never reset" posture (decision #5) for this release. Locked over a long design
session; this is the committed set.

**Locked decisions (supersede earlier forks where noted):**
- **Answer mode is per-card** — a single enum `Card.answerMode {flip, type, cloze}`.
  `Card.cardType` / `typeRaw` and the `CardType` enum are **deleted**; cloze is now an answer
  mode, not a card type. The deck holds a **default** (`Deck.defaultAnswerMode`, `flip`/`type`);
  cards inherit or override. **Supersedes the interim `type` enum (#2, #12)** — folded into `answerMode`.
- **Grading: 2-button permanently deleted → always 3-button (Again / Good / Easy).** Hard dropped
  from the UI. `GradingMode`, `Deck.gradingMode` / `gradingModeRaw` **deleted**; no grading-style
  axis. **Supersedes #7.** Grade source follows the mode: flip & cloze self-grade; type is
  app-checked (wrong → Again, correct → Good/Easy). `Grade.hard` stays in the enum for the
  schedulers but is never emitted by the UI.
- **Whole-card scheduling** unchanged (one schedule per card/direction); SM-2/FSRS untouched.
  Reverse only for single flip/type cards; cloze stays forward-only (extends #8).
- **Multiple-choice, multi-answer, and answer synonyms: dropped** (considered and cut).
- **Editor: one unified, graphical, structured (NOT WYSIWYG) mode-aware composer**; Markdown/
  LaTeX stay as text + live preview. Replaces `CardEditorView` + the bulk composer.
- **Multiple library folders (macOS):** the library aggregates a persisted set of folders;
  `LibraryLocation` → folder set; persist/prune **folder-scoped**; removal non-destructive; new
  decks land in a default folder. **iOS stays single-folder (deferred).**
- **Clean `.cards` format:** fresh `formatVersion`, all fields non-optional with defaults, no
  conditional stamping / no legacy reads. The runtime perf/equality machinery (the `modifiedAt`
  persist gate, byte-skip, reconcile content-equality) is **kept**.
- **First launch = fully clean slate, NO converter.** 1.8.0 reads only the new format (fresh
  `formatVersion`); old-format files are **ignored** by the loader (never read or pruned — safe),
  so the library starts empty. A one-time first-launch reset clears the review log + StudyStats
  (no streaks/history carried). **No legacy reader / converter ships** — the user has externally
  backed up their `.cards` files and will convert them in a future ground-up rebuild. (Reverses
  the brief converter idea — keep *nothing*: no cards, no progress, no history.)
- **Import/export: untouched** — deferred to a separate future engine revamp (confirmed it
  references none of the changing fields). AI generation of the new modes also deferred.

**Phase plan:**
1. **Foundation** — model (`AnswerMode`; delete `cardType`/`typeToAnswer`/`GradingMode`) + clean
   `DeckCodec` + first-launch move-aside/reset. Codec tests rewritten.
2. **Study** — per-card answer-mode resolution; 3-button grading (type keeps its check flow).
3. **Editor rebuild** — the unified graphical composer.
4. **Multi-folder (macOS)** — folder set + folder-scoped prune + Settings folders UI.
5. **Sweep + release** — green suite, snapshots, bump 1.8.0/19, Release build, /Applications, GitHub.

**Deferred to the NEXT iteration (post-1.8.0, NOT this release):** honest-grading polish
(retrieval-framed prompt, de-emphasized in-session scoreboard); type-in **near-miss
(edit-distance) tolerance** replacing the blanket "I actually knew it" escape; **default new decks
to `type`**; **typed single-blank cloze**; commit-before-reveal; response-latency signal;
calibration-driven honesty nudges; **iOS multi-folder**.

**STATUS (2026-06-08): Phase 1 (Foundation) DONE — on `main`, app + 307 tests green.** Commits:
`e463184` (docs), `4d4f38b` (1a — additive `AnswerMode`), `a02d319` (clean-slate decision),
`adf3632` (1b/c/d — delete `cardType`/`typeToAnswer`/`gradingMode`/`GradingMode`; clean **v4** codec
with a `decodeDTO` version guard so old files are ignored; **3-button** grading (Again/Good/Easy);
per-card type-in resolution; first-launch `StudyStats`+`ReviewLog` reset; tests remapped). Most of
**Phase 2** (study per-card mode + 3-button) landed with the cutover. **NEXT: Phase 3** (graphical
editor rebuild — `CardEditorView` got only a minimal compile-fix; `DeckEditorView` has the flip/type
default picker), then **Phase 4** (multi-folder macOS), then **Phase 5** (release: bump 1.8.0/19).

**STATUS (2026-06-08, cont'd): Phase 3 (editor) DONE.** `533820d` (3a — mode-aware composer: per-batch
flip/type/cloze picker, cloze field swaps in, mode-aware preview; pruned `PlaceholderTests`) and
`a309df0` (3b — unified add+edit into one composer via `BulkAddView(editing:)`; `CardEditorView`
retired). 306 tests green. **NEXT: Phase 4** (multiple library folders, macOS — `LibraryLocation` →
folder set; **folder-scoped prune** is the data-safety crux; new-deck destination; Settings → Folders
UI), then **Phase 5** (release: bump 1.8.0/19).

**STATUS (2026-06-08, cont'd): Phase 4 (multi-folder, macOS) core + UI DONE.** `cc1a1c7` (LibraryLocation
folder set + bookmark migration), `2960c70` (DeckStore multi-folder load/persist/reconcile + the
folder-scoped prune, with a prune-scoping safety test), `a51a0b5` (Settings → Folders add/remove UI +
`deleteAllDecksEverywhere`), plus **4c** — `DeckFolderWatcher` now watches **all** folders (one vnode
source each → one debounced reconcile; `RootView` re-points when `LibraryLocation.folders` changes), so
live external edits to secondary folders reflect instantly. **Phase 4 is COMPLETE.** 309 tests green.

**STATUS (2026-06-08, final): ALL PHASES COMPLETE — 1.8.0 shipped.** Phase 3's editor was rebuilt per the
corrected vision (the editable study card — see the "EDITOR VISION — CORRECTED" note above), then Phase 5
(release) was cut: bumped to **1.8.0 / build 20**, Release built, installed to `/Applications`, GitHub
release published. 312 tests green. (The one-time clean-slate wipe already ran at the 1.7.5 v4 baseline, so
updating to 1.8.0 is a normal incremental update — no further reset.)

---

**EDITOR VISION — CORRECTED (2026-06-08, after the user eyeballed 1.8.0):** the "graphical editor" shipped
as a **structured form** (answer-mode menu + labeled Front/Back/Elaboration fields). The user **rejected**
it on sight — *"I wanted a graphical UI for editing cards, instead I'm looking at a menu."* **The real
vision:** the editor surface **is the study card** — render the `FlashcardView` exactly as in study, and
edit the content **in place on the card** (WYSIWYG: front face → edit front; flip → edit back; cloze → edit
on-card with the blanks visible), with a **fixed layout** (the user must NOT move/drag parts — no canvas).
**Supersedes** the earlier structured-form decision. (Memory: `editor-vision`.)

**✅ DONE (2026-06-08) — the editable study-card editor shipped in 1.8.0.** `BulkAddView`'s editing surface
is now an `EditableFlashcard`: the real study-card chrome (shared with `FlashcardView` via the extracted
`StudyCardBackground`/`StudyCardLabel`/`StudyCardSectionChip` in `Features/Study/StudyCardChrome.swift`) with
the text editable **in place** on the card — front face → edit front; a **Flip pill** turns the card to edit
the back; **cloze** is a single face editing the `{{c1::…}}` markup with a live "in study" preview beneath.
The editable text is content-sized (`.fixedSize`) so a short term sits **centered like study** and the card
**grows** as you type (no internal scroll; zeroed text inset + a transparent macOS NSTextView). Add mode keeps
the **rapid front** (commit-on-Return adds the next card; delimited paste still splits into rows); edit mode
is a full multi-line editor. **All plumbing unchanged**: per-card `AnswerMode` resolution, cloze handling,
the `DeckCodec` v4 round-trip, the unified add/edit `editing:` path, and multi-folder persistence. The
answer-mode menu, section, and elaboration stay as a **minimal surround**. Snapshot `33_editable_card`;
312 tests green; verified live in all three modes. **Phase 5 (release) complete — shipped as v1.8.0 / build 20.**

**EDITOR VISION v3 — full-window GALLERY (2026-06-08, post-1.8.0, on `main`, UNRELEASED):** after seeing
the in-place card *in a sheet*, the user refined the vision again to a **full-window deck gallery** (à la
Finder/Photos): the selected card fills the top as the editable study card (the `EditableFlashcard` hero,
reused), a **filmstrip** of every card runs along the bottom (scrub with ← / → or click a thumbnail), and a
hover-animated **"+" tile** swooshes a fresh card into the deck. New `DeckGalleryView` (macOS), presented
full-window from `RootView` exactly like Study (`editorTarget`, watcher paused + reconcile-suppressed while
open). Edits go **live** to the cards (no draft/Save); persists on navigate/add/delete/close; blank "New
Card"s are pruned on close. **macOS uses the gallery; iOS keeps the `BulkAddView` sheet** (a filmstrip
doesn't fit a phone). All plumbing still unchanged (AnswerMode, cloze, DeckCodec v4, multi-folder). Entry
points route via `DeckDetailView.onEditCards` / `DeckCardListView.onOpenCard` (macOS → gallery; iOS → sheet).
Snapshot `34_gallery_editor` (chrome only — the filmstrip/editor are ImageRenderer-blank); verified live
(hero edit, flip, +/swoosh, thumbnails, ← / →, delete, close). 313 tests green. **RELEASED as v1.8.1 /
build 21** (2026-06-08) — shipped as-is; a **harmonization pass** (make the editor card render exactly like
the study card — see "EDITOR HARMONIZATION" below) is the next iteration on top of it.

**JSON import/export format switched (2026-06-08, RELEASED v1.8.1).** Per the user, the JSON
import/export format is now a bare card list **`{"cards":[{"front":…,"back":…,"source":…}]}`** (supersedes
the old `{"name":…,"cards":[{"term","definition","section"}]}`). `front`↔`term`, `back`↔`definition`,
**`source`↔`Card.section`** (the file's "source" values group cards into within-deck sections — added
`source` to `CardJSON.sectionKeys`). Export (`CardListCodec.exportJSON`) drops the top-level `name` (a
re-import takes its deck name from the filename) and writes front/back/source (source omitted when empty);
**import stays tolerant** of the old `term`/`definition`/`section` + `question`/`answer` keys. The format
has no field for a card's elaboration or answer mode, so those don't round-trip through JSON. **CSV is
untouched.** 314 tests (`parsesFrontBackSourceFormat` added; export tests updated).

**EDITOR HARMONIZATION — make the gallery card render exactly like the study card (NEXT, post-1.8.1).**
The user compared the gallery editor to study and wants them visually/functionally identical. Locked plan
(decisions made with the user):
- **The editor card IS the study card.** Render `FlashcardView` as the resting state of each face (same
  scaled font, **shrink-to-fit**, Markdown/LaTeX, section chip) instead of the separate `EditableFlashcard`
  text styling. Editing = a text-editor overlay on the *resting, un-rotated* face only (so the real **3D
  flip** can return — a rotated NSTextView mis-places its caret, but the editor only shows at net-0°).
- **Click a face → edit it (Obsidian "live preview" / source mode).** **Finish on click-away / Esc / Tab**
  → re-renders. Space/Return are just text. **No click-to-flip, no Space-to-flip in the editor.**
- **Flip = the button only**, kept at the **card's bottom**, redesigned (quiet/beautiful), with the
  shortcut **⌘↵** shown on it (NOT ⌘Space — that's the system Spotlight hotkey; the OS eats it).
- **Esc is two-stage:** exit edit if editing, else close the gallery.
- **Shared top bar** for study + gallery: **X on the left** for both, balanced, no dead space. **No divider**
  under the editor's bar. Mode picker → a **mode chip** with icons (Flip/Type/Cloze) — **not** segmented.
- **Elaboration only on the back** (render as study's `ElaborationPanel` when present; quiet "add" affordance
  when empty). Harmonize **size/aspect/padding** with study. ••• menu + chevron already match (leave as is).
- Known trade-off: a small size "pop" entering/leaving edit (comfortable editing size → study-scaled size);
  tune it. Add a faint "click to edit" cue for discoverability. iOS keeps the `BulkAddView` sheet.

**✅ BUILT (2026-06-09, on `main`, UNRELEASED).** New `EditableStudyCard` (gallery hero) renders at rest via
the shared `StudyCardText` + `StudyCardBackground` (extracted from `FlashcardView`, which now uses them too
— `studyCardFontSize` is the shared scale formula) → the at-rest card is pixel-identical to study (verified:
snapshot `34_gallery_editor` shows "User Stories" big/centered like `01_card_front`). Click a face → edit in
place (centered, content-sized editor); flip = button-only with **⌘↵** shown on it (3D flip, animated from
both rest and edit via a deferred toggle). Top bar: **X moved to the left in study too** (`StudySessionView`);
gallery divider removed; mode picker → a `modeChip` (icon + Flip/Type/Cloze menu, `AnswerMode.shortTitle`/
`symbolName`); elaboration shows only on the back. Cloze: masked (`Cloze.front`) at rest, raw `{{…}}` while
editing. **KEY GOTCHA:** a `TextEditor` inside a `rotation3DEffect` (even at 0°) can't take first-responder
focus, and setting `@FocusState` before the field is mounted reverts — so editing renders the active face
**flat** (no rotation) and an explicit `editingSide` @State mounts the editor, then focuses it via
`DispatchQueue.main.async`. 314 tests green; iOS `BulkAddView` untouched. **Known rough edges (eyeball):** a
faint stray scroller knob can show while editing (fragile AppKit scroll-view introspection); the size pop on
commit; cloze answer hidden at rest. **Awaiting the user's eyeball before release.**

---

## Cross-cutting foundations (apply to every epic)

- **CloudKit-safe invariants** (unchanged): every scalar defaulted, relationships
  optional with inverse, `.cascade` delete, no `@Attribute(.unique)`.
- **Persistence ripple:** any `Card`/`Deck` field change ⇒ update
  `Flashcards/Persistence/DeckCodec.swift` DTOs **and** bump the `.cards` format version.
  v1 + v2 files must still load.
- **Pure-core discipline:** schedulers, Elo, linters, and metric math are pure value-type
  functions with injected `now`/`calendar` (mirroring `SM2.swift`) so they're unit-tested
  off the main actor.
- **Test strategy:** unit tests for every pure core; `DeckCodec` round-trip + migration
  tests; `ImageRenderer` snapshot tests for new UI (see `FlashcardsTests/Snapshot*`).

---

## E0 — Quick wins (no migration, ship now) · Phase 0

High payoff-to-cost; de-risk the foundations by landing UX/flow improvements first.

### ☑ S0.1 — In-session requeue (learning-steps down payment)  · **Effort:** S · **Phase:** 0 · _shipped 2216498-440fea8_
- **Why:** Today a missed/new card vanishes until tomorrow (single-pass). Re-showing it
  within the session is the biggest acquisition win for the smallest change.
- **Touches:** `Flashcards/Features/Study/StudySession.swift` (the `advance()`/grade path,
  `items`/`index`).
- **Model/persist:** none.
- **Acceptance:** an `again`-graded card (and optionally any not-yet-graduated new card)
  reappears later in the *same* session (e.g. +N positions or end-of-queue); undo still
  restores exactly; practice mode behavior unchanged; covered by `StudySessionTests`.
- **Deps:** none. **Note:** superseded by native FSRS learning steps (S2.2) but worth
  shipping now.

### ☑ S0.2 — New-cards/day throttle  · **Effort:** M · **Phase:** 0 · _shipped; **global-only** — per-deck override deferred to Phase 1 (needs the v3 field). Default 20 (behavior change from unlimited)._
- **Why:** New cards are due at creation, so importing 500 cards floods the queue; the
  only governor is the blunt session cap. No graduated onboarding of new material.
- **Touches:** queue builders `Flashcards/Features/Study/TodayDetailView.swift:111` &
  `Flashcards/App/RootView.swift:202`; new per-day counter (mirror `StudyStats`
  UserDefaults day-log); Settings picker in `Flashcards/Features/Settings/SettingsView.swift`.
- **Model/persist:** none (UserDefaults counter).
- **Acceptance:** queue = all due reviews + up to **N** new (`lastReviewedAt == nil`);
  reopening study same day never re-introduces beyond N; per-deck override + global
  default; N=0 ⇒ unlimited; unit-tested split logic.
- **Deps:** none.

### ☑ S0.3 — Interleaving order  · **Effort:** S · **Phase:** 0 · _shipped; default on_
- **Why:** Pure due-date sort clusters related cards (correlated due dates); interleaving
  is a known desirable difficulty that aids discrimination.
- **Touches:** queue builders (same two files as S0.2); a pure `interleaved()` ordering.
- **Model/persist:** none (Settings toggle).
- **Acceptance:** within-day due set ordered round-robin across deck/section while keeping
  most-overdue-first for genuine backlog; toggle in Settings; pure + unit-tested.
- **Deps:** none.

### ☑ S0.4 — AI prompt rewrite + few-shot + linter warnings  · **Effort:** M · **Phase:** 0 · _shipped (`CardQualityLinter`)_
- **Why:** Prompt says "high-quality" but encodes zero card-design rules; output accepted
  with only dedup + empty-term filtering — risks low-quality, illusion-of-competence cards.
- **Touches:** `Flashcards/AI/CardJSON.swift` (system+user prompts); post-gen linter feeding
  warnings into `Flashcards/Features/AI/CardReviewList.swift`.
- **Model/persist:** none (richer fields come in S5.3).
- **Acceptance:** prompt encodes atomicity / minimum-information, ban yes-no &
  enumerations, precise-question fronts, short answers; includes good-vs-bad few-shot;
  linter flags over-long / list-like / near-duplicate / circular cards as *warnings*
  (non-blocking) in the review list; `AIProviderTests` cover the linter.
- **Deps:** none. Deepened later by S5.*.

### ☑ S0.5 — Metric-honesty relabel  · **Effort:** S · **Phase:** 0 · _shipped (deeper calibration/curves remain in E6)_
- **Why:** "X% recall now" is schedule-derived (`0.9^(elapsed/interval)`) and reads ~100%
  right after studying — it measures "am I behind?" not "do I know this?" Risks a false
  sense of mastery.
- **Touches:** `Flashcards/Features/Study/StatsView.swift`,
  `Flashcards/Features/DeckDetail/DeckHeaderView.swift`, `StudyInsights.swift` takeaway.
- **Model/persist:** none.
- **Acceptance:** measured **true-retention** leads where available; predicted recall
  explicitly labeled an *estimate*; the just-studied ~100% case is suppressed or reframed
  ("next due in…"). Full calibration/real curves land in E6.
- **Deps:** none.

---

## E1 — Foundational enablers (format v3) · Phase 1

One batched migration. Land these together; everything in Phase 2 builds on them.

### ☑ S1.1 — `Scheduler` protocol; plug SM-2 behind it  · **Effort:** M · **Phase:** 1 · _shipped_
- **Why:** Clean seam to swap/select algorithms per deck without touching the study engine.
- **Touches:** new `Flashcards/Scheduling/Scheduler.swift`; refactor `SM2.swift` to conform;
  `Card+Scheduling.swift`; `StudySession.grade()` calls the protocol.
- **Model/persist:** none yet (selection field added with S1.2/S2.4).
- **Acceptance:** `Scheduler` protocol over `SchedulingState`; `SM2` conforms; existing
  `SM2Tests`/`StudySessionTests` pass unchanged; injected `now` preserved.
- **Deps:** none.

### ☑ S1.2 — FSRS state fields on `Card` (per direction)  · **Effort:** S · **Phase:** 1 · _shipped; S/D seeding from SM-2 deferred to S2.5_
- **Why:** FSRS needs stability + difficulty per direction; SM-2 ignores them.
- **Touches:** `Flashcards/Models/Card.swift` (add `stability`, `difficulty`, +`reverse…`,
  defaulted); `Card+Scheduling.swift` accessors.
- **Model/persist:** **v3** — codec + migration (S1.6).
- **Acceptance:** fields present, defaulted, CloudKit-safe; SM-2 path unaffected.
- **Deps:** none (migrate in S1.6).

### ☑ S1.3 — Review-log sidecar store  · **Effort:** M · **Phase:** 1 · _shipped (`ReviewLog`)_
- **Why:** Only each card's *last* review is stored today (no history). FSRS optimization,
  calibration, real retention curves, Elo trajectory, and coverage trends all need
  per-review records.
- **Touches:** new `Flashcards/Persistence/ReviewLog.swift` (append-only `reviewlog.jsonl`
  in the library folder); write hook in `StudySessionView.performGrade`/`performUndo`;
  reader for analytics.
- **Model/persist:** new sidecar file (not in `.cards`); tolerate missing/partial log.
- **Acceptance:** each non-practice grade appends `{cardID, direction, ts, grade, elapsed,
  prevInterval/stability, mature}`; undo appends a compensating/void record (no rewrite);
  reader aggregates by card/topic/day; corrupt lines skipped; unit-tested.
- **Deps:** none. Enables S2.7, S6.2, S6.5, S7.2.

### ✖ S1.4 — Tags on `Card`  · _DROPPED — field deleted; Subject/Deck/Section used instead (see decision #9)._
- **Why:** Cheapest unit of relational structure; unlocks cross-deck topic study and the
  coverage/mastery denominator (E6) and per-topic Elo (E7).
- **Touches:** `Card.swift` (`tags: [String] = []`); `DeckCodec`; editors
  (`CardEditorView`, `BulkAddView`).
- **Model/persist:** **v3**.
- **Acceptance:** tags persist round-trip; editable in card editors; CloudKit-safe default.
- **Deps:** migrate in S1.6. Used by S4.1, S6.3, S7.3.

### ☑ S1.5 — `extra` / example field on `Card`  · **Effort:** S · **Phase:** 1 · _shipped end-to-end: model+codec, plus the answer-side `ElaborationPanel` + a card-editor field (B1)_
- **Why:** Foundation for application/elaboration cards (worked examples, why/how) shown on
  the answer side — bridges recall toward transfer.
- **Touches:** `Card.swift` (`extra: String = ""`); `DeckCodec`; `FlashcardView` answer face
  (renders via existing Markdown/LaTeX); editors.
- **Model/persist:** **v3**.
- **Acceptance:** optional extra renders under the answer when present; round-trips;
  Markdown+LaTeX honored.
- **Deps:** migrate in S1.6. Used by S5.6.

### ☑ S1.6 — `DeckCodec` + format v3 + seed-migration + tests  · **Effort:** M · **Phase:** 1 · _shipped; conditional v3 stamping ⇒ zero phantom edits on v2 files_
- **Why:** Single batched migration carrying S1.2/S1.4/S1.5 (+ interim cloze type if S3.2
  lands here).
- **Touches:** `Flashcards/Persistence/DeckCodec.swift`, format-version constant,
  `DeckStore` load path; `DeckStoreTests`/codec tests.
- **Model/persist:** writes **v3**; **loads v1 + v2 + v3**.
- **Acceptance:** v1/v2 files load and round-trip to v3 with **zero data loss**; new fields
  default on old files; FSRS S/D seeded from existing interval/ease (S2.5) on first load;
  migration covered by tests.
- **Deps:** S1.2, S1.4, S1.5 (+ S3.2 if folded in).

---

## E2 — FSRS scheduler (closes gaps 1, 2, 3, 6) · Phase 2

### ☑ S2.1 — Port FSRS algorithm  · **Phase:** 2 · _shipped **FSRS-6**, validated vs py-fsrs 6.3.1 to <0.001 (matchesPyFSRS6ReferenceVectors), now the **default for new decks** (existing stay SM-2)._
- **Why:** Modern, ~20–30% more efficient scheduling; principled stability/difficulty model.
- **Touches:** new `Flashcards/Scheduling/FSRS.swift` (pure), conforming to `Scheduler`.
- **Model/persist:** uses S1.2 fields.
- **Acceptance:** port published FSRS reference (default weights, **no training**);
  retrievability `R(t)` from stability + elapsed; schedules to a configurable target
  retention; pure + injected `now`; comprehensive `FSRSTests` (known vectors).
- **Deps:** S1.1, S1.2.

### ☐ S2.2 — Native learning / relearning steps  · **Effort:** M · **Phase:** 2
- **Why:** Proper short-spaced steps for new and lapsed cards (replaces S0.1 stopgap).
- **Touches:** `FSRS.swift` (learning phase), `StudySession` (sub-day requeue),
  **bypass the start-of-day snap** (`SM2.swift:62` analog) for sub-day intervals.
- **Model/persist:** learning phase derivable from S/D + reps; add a phase marker only if
  needed (fold into v3).
- **Acceptance:** configurable steps (e.g. 1m/10m); new + lapsed cards re-shown intra-
  session; graduation to day-scale intervals; start-of-day snap only for ≥1d.
- **Deps:** S2.1.

### ☐ S2.3 — Graded lapse handling  · **Effort:** S · **Phase:** 2
- **Why:** A missed mature card should lose stability, not reset to a 1-day interval with a
  large flat ease hit.
- **Touches:** `FSRS.swift` post-lapse stability.
- **Acceptance:** lapse reduces stability per FSRS (interval shrinks proportionally, not to
  1d); covered by tests at multiple maturities.
- **Deps:** S2.1.

### ☑ S2.4 — Per-deck scheduler selection  · **Effort:** M · **Phase:** 2 · _shipped; default SM-2, FSRS opt-in via the deck editor; session resolves per-item_
- **Why:** Roll out FSRS gradually; keep SM-2 selectable.
- **Touches:** `Deck.swift` (`schedulerRaw` defaulted), `DeckCodec`, Settings/deck editor,
  `StudySessionView`/queue resolve the deck's scheduler.
- **Model/persist:** **v3** field (fold into S1.6 batch).
- **Acceptance:** new decks default FSRS; existing decks keep working (SM-2 until migrated/
  opted in); switch is non-destructive.
- **Deps:** S1.1, S2.1.

### ☑ S2.5 — Seed FSRS S/D from existing SM-2 state  · **Effort:** S · **Phase:** 2 · _shipped; FSRS seeds S from interval, D from ease on first run_
- **Why:** Preserve years of progress when a deck moves to FSRS.
- **Touches:** migration in `FSRS.swift`/`DeckCodec` (runs in S1.6 load path).
- **Acceptance:** initial stability/difficulty derived from current interval/ease so the
  first FSRS interval is continuous with the old schedule (no mass re-due); tested.
- **Deps:** S2.1, S1.6.

### ☑ S2.6 — Grading UI under FSRS  · **Effort:** S · **Phase:** 2 · _no change needed: the per-deck 2-/4-button grading already feeds FSRS (rating 1–4); default stays 2-button (decision #7)_
- **Why:** FSRS reads binary or 4-grade natively (no manual ease), dissolving the two-
  button signal-loss problem — decide the default.
- **Touches:** `GradingMode.swift`, `StudyControlsBar`, deck setting.
- **Acceptance:** both 2- and 4-button feed FSRS correctly; documented default; no EF-only-
  decays pathology remains.
- **Deps:** S2.1.

### ☑ S2.7 — FSRS weight optimization from review log  · **Effort:** XL · **Phase:** 3 · _shipped: `FSRSOptimizer` (BCE loss + Adam w/ numerical gradients + L2-to-default), `FSRSWeights` store, Settings → Spaced Repetition "Tune FSRS to my reviews" (off-main, gated at 100 reviews)_
- **Why:** Per-user-tuned weights beat defaults — and make richer rating signals (type-in Hard/Good/Easy) pay off.
- **Touches:** `FSRSOptimizer` over `reviewlog.jsonl`; `FSRSWeights` (UserDefaults); `SchedulerKind.fsrs` injects them; Settings control + reset.
- **Acceptance:** opt-in; needs sufficient history; falls back to defaults; runs off the main thread. ✓
- **Deps:** S1.3, S2.1.

---

## E3 — Content model: card types · Phase 2 (interim) / Phase 3 (full)

### ☑ S3.1 — `Card.type` enum (basic | cloze | typeIn)  · **Effort:** S · **Phase:** 2 · _shipped (basic/cloze; typeIn deferred to S3.3)_
- **Why:** Interim path to multiple card types without the full Note refactor.
- **Touches:** `Card.swift` (`typeRaw` defaulted), `DeckCodec`, `ReviewItem`/`Deck.allReviewItems`.
- **Model/persist:** **v3** (fold into S1.6).
- **Acceptance:** type persists; defaults to basic; unknown raw ⇒ basic.
- **Deps:** S1.6.

### ☑ S3.2 — Cloze deletion (interim, ReviewItem expansion)  · **Effort:** M · **Phase:** 2 · _shipped as hide-all whole-card cloze (decision #8); per-cloze units deferred_
- **Why:** The single most valuable missing type — atomic recall *in context*, the bridge
  toward relational knowledge; also raises AI-card quality.
- **Touches:** cloze parser (`{{c1::…}}`), `Deck.allReviewItems`/`ReviewItem` expand one
  cloze card into one item per index (mirrors forward/reverse), `FlashcardView` masks the
  active cloze; per-cloze scheduling state stored as a small per-index array (or whole-card
  for v1).
- **Model/persist:** cloze text in `term`; per-index state decision documented.
- **Acceptance:** a cloze card yields N study items; correct span masked on the front,
  revealed on flip; scheduled independently (or as one unit for v1, with a tracked TODO);
  Markdown+LaTeX intact; unit + snapshot tested.
- **Deps:** S3.1.

### ☑ S3.3 — Type-in-answer  · **Effort:** M · **Phase:** 2 · _shipped: per-deck "Type the answer" mode; `AnswerCheck` normalized comparison; ✓/✗ hint feeds the normal self-grade_
- **Why:** Forces *production*, not just recognition; cheap active-recall upgrade.
- **Touches:** `StudySessionView` answer field + result row; `AnswerCheck` (case/space-tolerant,
  trailing-period-forgiving, accents significant); `Deck.typeToAnswer` (v3) + deck-editor toggle;
  the learner still self-grades (the match is a hint, not the grade).
- **Acceptance:** typed answer compared case/space-insensitively; near-miss shown; feeds the
  normal grade path; cloze cards keep their fill-in style. Unit + snapshot tested.
- **Deps:** S3.1.

### ☑ S3.4 — Sibling burying  · **Effort:** S · **Phase:** 2/3 · _shipped: `StudySession.buryingSiblings` (stable greedy, default gap 3) applied per-segment in `prioritizingReviews` + the practice path; requeue insertion nudged past a same-card neighbor. No-op for forward-only decks._
- **Why:** Don't show cards from the same source (cloze siblings / forward+reverse) back-to-
  back — leaks answers, reduces value.
- **Touches:** queue builders / interleave ordering (S0.3).
- **Acceptance:** same-card/same-note items separated within a session where possible.
- **Deps:** S0.3, S3.2.

### ☐ S3.5 — Full `Note`-above-`Card` refactor  · **Effort:** XL · **Phase:** 3
- **Why:** Proper backbone: a Note holds fields and generates typed cards; foundation for
  richer relations, robust cloze, and shared content.
- **Touches:** new `Note` `@Model`; `Card` references `Note`; `DeckCodec` **v4**; broad UI.
- **Acceptance:** notes generate cards; existing cards migrate to single-field notes with
  zero loss; cloze/typeIn re-homed onto notes.
- **Deps:** validated demand from S3.2/S3.3.

### ☐ S3.6 — Image-occlusion / MCQ  · **Effort:** XL · **Phase:** 3
- **Why:** Visual/diagram learning; distractor-based recognition.
- **Deps:** image support on cards (not yet present) + S3.5. **Note:** big; gated on demand.

---

## E4 — Relational structure · Phase 2 / Phase 3

### ☐ S4.1 — Tag UI + tag-filtered study  · **Effort:** M · **Phase:** 2
- **Why:** Cross-deck topic study ("all `krebs-cycle` cards") and the unit for coverage/Elo.
- **Touches:** tag chips in editors/library; a tag-scoped `StudyPlan` (queue builder filters
  by tag across decks).
- **Acceptance:** study/practice any tag across decks; tag browser; counts per tag.
- **Deps:** S1.4.

### ☐ S4.2 — Prerequisite DAG / concept graph  · **Effort:** XL · **Phase:** 3
- **Why:** The real "expertise scaffolding" — gate new-card introduction on prerequisites.
- **Touches:** edge model between cards/notes/tags; cycle detection; introduction order in
  the new-card throttle (S0.2).
- **Acceptance:** authorable prereq edges; new cards held until prereqs mature; no cycles.
- **Deps:** S0.2, S1.4 (and ideally S3.5). **Note:** authoring burden — validate first.

---

## E5 — AI generation quality (gap 11) · Phase 2

### ☐ S5.1 — Card-design rules in system prompt  · **Effort:** S · **Phase:** 2 *(lands early via S0.4)*
- Encodes atomicity/minimum-information, ban yes-no & enumerations, precise fronts, short
  answers. **Touches:** `CardJSON.swift`. **Deps:** none.

### ☐ S5.2 — Few-shot good/bad exemplars  · **Effort:** S · **Phase:** 2 *(with S0.4)*
- Highest-leverage prompt change. **Touches:** `CardJSON.swift`.

### ☐ S5.3 — Emit `cloze` + `extra` in `GeneratedCard`  · **Effort:** M · **Phase:** 2
- **Why:** Let the model produce cloze and worked examples, not just term/definition.
- **Touches:** `Flashcards/AI/GeneratedCard.swift`, `CardJSON.swift` parsing, review/add path
  in `AIGenerationView`.
- **Acceptance:** generated cloze/extra flow through review→add into S3.2/S1.5 fields.
- **Deps:** S3.2, S1.5.

### ☐ S5.4 — Post-gen quality linter (warnings)  · **Effort:** S · **Phase:** 2 *(with S0.4)*
- Flags over-long/list-like/near-duplicate/circular cards in `CardReviewList`. **Deps:** none.

### ☐ S5.5 — Optional critic pass  · **Effort:** M · **Phase:** 3
- Second model call grades its own cards against the rules. **Trade-off:** ~2× cost; opt-in.

### ☑ S5.6 — Application / elaboration generation  · **Effort:** M · **Phase:** 2 · _shipped: a "Test understanding" intent (why/how/apply/predict) that fills the `extra` field; "Key facts" stays the default_
- **Why:** Generate why/how/worked-example cards (transfer), using the `extra` field.
- **Touches:** `GenerationIntent` + a card-style picker in `AIGenerationView`; recall vs
  understanding prompts in `CardJSON.swift`; `extra` parsed (tolerant keys) and saved;
  editable in `CardReviewList`. **Deps:** S1.5, S5.1.

---

## E6 — Honest metrics, coverage & depth (gaps 7, 12) · Phase 2

### ☐ S6.1 — Lead with measured true-retention  · **Effort:** S · **Phase:** 2
- Deepens S0.5 using the review log. **Touches:** `StudyInsights`, `StatsView`,
  `DeckHeaderView`. **Deps:** S1.3.

### ◐ S6.2 — Calibration curve (predicted vs actual)  · **Effort:** M · **Phase:** 2 · _engine + Insights takeaway shipped (`Calibration`, review-log's first consumer); per-bucket curve chart still to add_
- **Why:** The honest "is my sense of mastery real?" meter — compares predicted recall to
  actual pass rate. **Touches:** `StudyInsights` (new aggregation over `reviewlog.jsonl`),
  `StatsView` chart. **Deps:** S1.3.

### ☐ S6.3 — Per-topic coverage & mastery  · **Effort:** M · **Phase:** 2
- **Why:** Coverage needs a denominator → tags. "Krebs cycle: 12 cards · 80% mature · 91%
  retention." **Touches:** `StudyInsights` per-tag aggregation; `StatsView` breakdown.
- **Deps:** S1.4, S1.3.

### ☐ S6.4 — Goals + projected completion  · **Effort:** M · **Phase:** 2/3
- **Why:** "All mature by date X," projected from the existing due-forecast. **Touches:**
  `StudyInsights.dueForecast` (already computed), goal store, `StatsView`. **Deps:** S6.3.

### ☐ S6.5 — Real retention curves from log  · **Effort:** M · **Phase:** 3
- Replace schedule-derived `0.9^(t/interval)` displays with measured forgetting curves.
  **Deps:** S1.3.

---

## E7 — Adaptive practice / exam-cram mode + difficulty metric (Elo) · Phase 2

Elo is a **measurement + selection** layer, explicitly **not** the spaced scheduler.

### ☑ S7.1 — Elo / Glicko engine (pure)  · **Effort:** M · **Phase:** 2 · _shipped (`Elo`); plain Elo for v1, Glicko RD refinement deferred_
- **Why:** Learner ability θ per topic + card difficulty `d` per direction, on one scale.
- **Touches:** new `Flashcards/Scheduling/Elo.swift` (or `Insights/`): pure update
  `E=1/(1+10^((d−θ)/400))`, `θ←θ+K(S−E)`, `d←d−K(S−E)`; decaying/confidence-aware **K**
  (consider Glicko rating-deviation so new items read `1500±350`, not false precision).
- **Model/persist:** card difficulty per direction on `Card` (**v3**, fold into S1.6);
  per-topic ability in a small store (sidecar/UserDefaults).
- **Acceptance:** deterministic, injected inputs; `EloTests` with known sequences; ratings
  reproducible/back-fillable from the review log.
- **Deps:** S1.4 (topics), S1.6 (difficulty field).

### ☑ S7.2 — Drive Elo from the review log  · **Effort:** S · **Phase:** 2 · _shipped (`Elo.replay`)_
- Back-fill + live update ratings from `reviewlog.jsonl` so they're reproducible.
  **Deps:** S1.3, S7.1.

### ☑ S7.3 — Difficulty / mastery as surfaced metrics  · **Effort:** M · **Phase:** 2 · _shipped: Mastery % on the deck page (Elo) + a "Weak spots" card on Insights (`FocusInsights`) ranking your shakiest cards with a one-tap weakest-first drill_
- **Why:** Per-topic ability score + trajectory ("Biology 1480 ↑60/mo") is the most
  expertise-*feeling* signal; per-card difficulty aids review. Under FSRS, prefer FSRS-`D`
  for *card* difficulty and reserve Elo for the *learner-ability* score to avoid double-
  counting.
- **Touches:** `StatsView`, deck/card detail.
- **Acceptance:** ability per topic with confidence + trend; card difficulty shown; clearly
  framed as engagement/insight, not the schedule.
- **Deps:** S7.1, S6.3.

### ☑ S7.4 — Leech detection  · **Effort:** S · **Phase:** 2 · _shipped (whole-card `lapses` Int + `suspended`, format v3; `Card.leechThreshold` = 8; Again-grade increment in `StudySession` with undo; leech/suspended badge in the deck list + Suspend/Reset in the card editor; suspended cards excluded from `Deck.allReviewItems`)_
- **Why:** Flag broken cards to suspend/reformulate. **Primary signal:** lapse counter
  (add `lapses` Int, **v3**); difficulty corroborates. **Touches:** `Card.swift`,
  `StudySession` (increment on `again`), surfacing in deck detail.
- **Acceptance:** card flagged at a lapse threshold (default ~8); user can suspend/reset/edit.
- **Decision:** a single **whole-card** `lapses` (not per-direction) — a leech is reformulated as a
  whole, and the failed-recall signal reads the same in either direction.
- **Deps:** S1.6.

### ☑ S7.5 — Adaptive practice selection (Elo-matched)  · **Effort:** M · **Phase:** 2 · _shipped (`Elo.adaptiveOrder`, weakest-first; forced practice)_
- **Why:** The one load-bearing use of Elo: pick/order *non-due* cards so success ≈ target
  (~85%, desirable-difficulty sweet spot).
- **Touches:** a new practice `StudyPlan` selector using θ vs `d`; reuses Practice mode
  (schedules untouched — `StudySession.isPractice`).
- **Acceptance:** practice run prioritizes weakest-relative-to-ability cards, ordered near
  target success; never advances the spaced schedule; tag/deck scoped.
- **Deps:** S7.1, S4.1.

### ☑ S7.6 — Exam-cram mode UX  · **Effort:** M · **Phase:** 2 · _shipped (deck ••• → Adaptive Practice); optional exam-date input still to add_
- **Why:** Product surface for S7.5 — "drill `tag/deck` before <exam date>."
- **Touches:** entry point in library/deck menu; optional exam-date input; surfaces weakest
  topics; wraps S7.5 selection.
- **Acceptance:** pick scope (+ optional date), drill adaptively over not-necessarily-due
  cards; summary highlights remaining weak areas.
- **Deps:** S7.5.

---

## Phase plan (sequencing)

- **Phase 0 — ✅ DONE (zero migration):** S0.1–S0.5 shipped to `main`. *(Also landed S5.1/S5.2/S5.4 content via S0.4.)*
- **Phase 1 — ✅ DONE (format v2→v3):** S1.1–S1.6 shipped. (S2.4/S3.1/S7.1/S7.4 fields fold into a later migration as they land.)
- **Phase 2 — 🚧 in progress:** **FSRS shipped end-to-end** (S2.1 algorithm · S2.4 per-deck
  selection · S2.5 SM-2 seeding · S2.6 grading) — opt-in per deck, default SM-2. **Remaining
  before FSRS can become the default:** exact-vector validation vs. py-fsrs (the S2.1 caveat),
  and S2.7 weight optimization (Phase 3). Then S3.1–S3.4 (cloze/type-in) · E4.1 · E5 · E6
  (metrics/coverage) · E7 (Elo practice + difficulty).
- **Phase 3 — ambitious/optional:** S2.7 · S3.5/S3.6 (Note refactor, occlusion/MCQ) ·
  S4.2 (prereq DAG) · S5.5 · S6.5.

**Critical path to the headline outcomes:** S1.1→S1.2→S1.6→S2.1 (FSRS) ·
S1.3 (log) → E6 (honesty) · S1.4 (tags) + S1.6 → S7.1 → S7.5 → S7.6 (exam-cram).

---

## Resolved decisions

All eight former open decisions are resolved — see **Decision log items 6–13** above
(FSRS source/target retention · 2-button default · whole-card cloze v1 · tags as the
topic unit · Glicko confidence · ≥8-lapse leech · interim `type` enum · one global
review log). Revisit any of them if real-world results disagree; none are load-bearing
enough to block Phase 0.

---

## Known issues (found in Phase 0 hand-testing)

- **KI-1 — Today count vs. actually-studied count mismatch (minor; revisit).** Reported:
  100+ due in **Today**, but a capped session studied only **18** (not the 20 cap). Most
  likely the S0.2 new-card throttle interacting with the unthrottled count: a session is
  `due reviews + min(newPerDay − introducedToday, available new)`, while the Today header
  shows **all** due cards unthrottled. So a Today queue dominated by new cards (e.g. right
  after loading the 60-card New Flood deck), with some new already introduced earlier today,
  yields fewer than the session cap. **Needs confirmation** of the exact composition. Proper
  fix rides with **E6** (honest counts) — surface a "X due · ≤N new today" breakdown or show
  the actually-studyable count, so the header doesn't overstate what a session will present.
- **KI-2 — Interleave toggle has no effect on practice runs. ✅ RESOLVED** (ce3d7fa — practice runs now honor the toggle). S0.3 applied interleaving only
  to the *due* queue; the practice path (nothing due → `deck.allReviewItems`) is returned
  untouched, so toggling interleave does nothing when re-studying an already-cleared deck.
  Options: extend interleaving to practice runs, or just document it. (For now, test interleave
  with *due* cards — Reset Progress between runs.)

## Risk register

- **Migration data loss (high impact):** mitigate with exhaustive v1/v2→v3 round-trip tests
  before writing v3; never delete a file that fails to decode (existing `DeckStore` prune
  invariant).
- **FSRS scheduling regressions:** keep SM-2 selectable (S2.4); A/B per deck; seed-migrate
  (S2.5) to avoid mass re-due.
- **Elo/FSRS difficulty double-counting:** assign FSRS-`D` = card difficulty, Elo = learner
  ability (S7.3); don't let Elo touch the spaced schedule.
- **Metric churn confusing users:** relabel (S0.5) before adding new charts (E6).
- **Scope creep on Note refactor / DAG (XL):** gated to Phase 3, demand-validated.

---

*Last updated by the learning-efficacy audit. Edit in place as stories land; keep statuses
current (multiple sessions rely on this file — see `CLAUDE.md` on syncing `main`).*
