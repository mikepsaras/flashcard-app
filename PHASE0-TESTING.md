# Testing Phase 0 by hand

Phase 0 changed study-queue behavior and metric wording. The hard part of testing it is
having realistic data; the developer tools now seed exactly what's needed.

## Setup (once)

1. **Settings → About →** tap the version **7×** to unlock **Developer** mode.
2. In the **Developer** section:
   - **Load Phase 0 test set** — three throwaway decks (under a "Test Data" library
     section) built for S0.1–S0.3.
   - **Seed review history** — ~3 years of synthetic activity, so the S0.5 retention
     metrics populate. *(Replaces existing stats — it's a dev tool.)*
   - Optionally **Load sample library** for a broader, mixed library.
3. When done: **Remove all test data** deletes the "Test Data" decks and clears seeded stats.

The Developer footer shows a live readout: **New introduced today: N of LIMIT · interleave on/off**.

---

## S0.1 — In-session requeue (a miss comes back)

- Study **③ Miss & Requeue**. Note the header "**X of Y**" total.
- Flip a card and grade it **✕ (Don't know)**.
- **Expect:** the run's total grows by one, and that same card reappears a few cards
  later this session (instead of vanishing until tomorrow). Grading it ✓ the second time
  ends the run. **Undo** on the missed card removes the extra copy again.
- Practice runs (study a deck with nothing due) **don't** requeue — schedules are untouched.

## S0.2 — New-cards/day throttle

- Make sure **Settings → Studying → New cards per day** is a finite number (default **20**).
- Study **① New Flood** (60 brand-new cards).
- **Expect:** you're shown about **20** new cards, then "caught up" — not all 60. Re-open
  the deck the same day: **0** new (until tomorrow). The Developer readout shows
  **New introduced today** climb to the limit and stop. Set the limit to **Unlimited** to
  confirm all 60 flow through.
- Reviews are never throttled — only first-time cards — and always come **before** new cards.

## S0.3 — Interleaving

- Study **② Interleave Demo** (sections Alpha / Beta / Gamma, all due) with **Interleave topics ON**.
- **Expect:** the section chip **round-robins** Alpha → Beta → Gamma → Alpha → … instead of all
  of Alpha first. This deterministic A→B→C cycle is the reliable signal.
- To compare with the toggle OFF, the cards must be **due** — first **Reset Progress** (study
  screen ••• → Reset Progress) or reload the test set. A plain re-study after grading the cards
  is a *practice* run, which doesn't apply interleaving at all (see KI-2 in BACKLOG.md), so the
  toggle appears to do nothing. With the toggle OFF the order is the stored due order (not
  guaranteed to look clustered), so trust the ON = round-robin signal.
- Cross-deck: the **Today** queue interleaves across *decks* the same way.

## S0.4 — AI card-quality linter

- **Developer → Preview card linter** (no API key needed).
- **Expect:** orange warnings under the sample cards — a circular answer, a list/enumeration,
  an over-long answer, a missing answer, and a near-duplicate pair — while a clean card has
  none. Editing a card updates its warnings live.
- With a real API key (Settings → AI), the same warnings appear in **New Deck from Notes →
  review** on generated cards.

## S0.5 — Honest metrics

- Open **Insights** (after **Seed review history**).
- **Expect:** the Memory card's takeaway **leads with measured** mature-card retention, and
  predicted recall is framed as "**a projection from your schedule, not a measurement**".
  The legend reads "**est. recall now**" beside "mature retention". The deck page ring caption
  reads "**est. recall …**".
- Sanity check the estimate's optimism: study a deck to completion, then look at its ring —
  right after studying it reads near 100% ("est."), which is exactly the schedule-derived
  optimism the relabel is meant to flag.
