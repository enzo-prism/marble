# Ask your journal

A private, on-device question box over the lifter's own training history.
Entry point: **Log → Workout History → toolbar Ask button** (`Ask.Button`;
SF Symbol `apple.intelligence` when Apple Intelligence will write the answer,
`text.magnifyingglass` otherwise). It opens `AskJournalSheet`.

## What it answers

| Question shape | Engine query | Example |
| --- | --- | --- |
| Last time (optionally at/above a weight) | `.lastPerformed` | "When did I last bench?", "last time I squatted 100 kg" |
| Best set | `.best` (heaviest / most reps / fastest / longest / automatic) | "What's my heaviest deadlift?", "fastest 100m sprint" |
| Counts and volume in a period | `.totals` (all exercises or one) | "How many sets did I do this week?", "bench volume last month" |
| Most recent workout matching a name or exercise | `.recentSession` | "When was my last leg day?" |
| Workouts in a period | `.sessions` | "What did I train last week?" |

Periods: today, yesterday, this/last week/month/year, last/past N days/weeks/months,
month names ("in October", "january 2024"), ISO dates and ranges
("2026-11-01 to 2026-11-10", "since 2026-11-01"), all time / ever.

Anything else gets an honest "Marble can answer questions about…" plus tappable examples.

## Doctrine (same as `TrainingInsights`)

1. **Every number is computed in code.** `JournalQueryEngine` runs bounded SwiftData
   fetches and returns facts (plain text), a template sentence, and `JournalCard`s.
   Weights are compared in kilograms (`PersonalRecords.kilograms`) and shown in the
   preferred unit; converted values round to 0.1 and the card/facts carry the logged
   original ("logged as 100 kg"). Dumbbell pairs show per hand. Sprint times use the
   tenths canon (`SprintRepDetail` where present, whole seconds × 10 otherwise).
   Ties follow `PersonalRecords` (heavier → more reps → later set; fastest tie → later rep).
   Imported sets count like manual ones and are labelled "Imported from …".
2. **The model only chooses tools and words.** `AskJournalModel` gives a
   `LanguageModelSession` four tools (`findLastTime`, `findBest`, `countTraining`,
   `findWorkouts`) that call `AskJournalLedger` → the engine. Greedy sampling,
   ≤160 response tokens, ≤4 tool calls (the 5th throws and ends the turn), a 15 s
   deadline that returns even if the framework ignores cancellation, and the turn
   is cancelled when the user asks again, taps Cancel, or closes the sheet.
   A single time phrase in the question outranks the model's period; a confident
   library match for the model's exercise name wins, else the exercise the question
   names. Distances for "fastest" come from the question only.
3. **The model's sentence is not trusted.** `AskAnswerValidator` (built on
   `InsightValidator`) requires every number in the reply to appear in the tool
   outputs, blocks the insight blocklist plus advice/hedging words ("should",
   "recommend", "roughly", "health", …), emoji and links, and keeps at most two
   sentences (the first must pass). No tool call → no model answer.
4. **Always verifiable.** Cards are rendered from tool/engine output, never model
   text, and tap through to the workout (`WorkoutSessionDetailView`) or the
   exercise's progress (`ExerciseProgressView`).
5. **Deterministic fallback.** Model unavailable, unsupported locale, circuit
   breaker open, error, timeout, or validation failure → `JournalQuestionMatcher`
   (keyword intents + `ExerciseMatcher` + `JournalTimeParser`) → engine → template
   sentence. If the model's tools found something the matcher can't reach, that
   result is shown in the engine's own words.
6. **Honest footer.** "Answered on this device from your journal." plus
   "Written with Apple Intelligence." only when the model's sentence is shown.

Privacy: no network, no Private Cloud Compute, no persistence (schema stays V6),
no analytics. Hard model failures trip the shared `ModelCircuitBreaker` used by
the scan parser; Ask's own limits (deadline, tool cap) never do. The model is
never used in XCTest or UI-test processes, so tests and snapshots are deterministic.

## Fetch bounds

- Last time: `fetchLimit = 1`; with a weight threshold, 200-row newest-first pages
  until a match.
- Bests and per-exercise totals: predicate on exercise + period.
- Workout lists: `fetchCount` + `fetchLimit = 5`; latest match reuses
  `WorkoutHistoryQuery.descriptor`.
- All-time totals across all exercises scan every set, fetching only
  `performedAt`, `weight`, `weightUnit`, `reps`.

## Limits

- English phrasing in the deterministic matcher, facts and templates.
- No comparisons ("this week vs last week") in the fallback; the model may call
  `countTraining` twice for those.
- "Workouts" means recorded `WorkoutSession`s; sets logged outside a workout count
  as sets and training days, and empty workout lists say so.
- Estimated 1RMs, body metrics, supplements and sprint goal hit rates are out of scope.

## Files

`marble/Features/Ask/` — `JournalQuery.swift` (periods, queries, cards, formatting),
`JournalQuestionMatcher.swift` (time parser + fallback matcher),
`JournalQueryEngine.swift`, `AskAnswerValidator.swift`,
`AskJournalModel.swift` (responder, ledger, tools, deadline), `AskJournalSheet.swift`.
Tests: `JournalQueryEngineTests`, `JournalQuestionMatcherTests`, `AskJournalTests`.

## Needs a real Apple Intelligence device

Tool selection and argument quality, reply phrasing and how often validation
falls back, latency against the 15 s deadline, guardrail behaviour on gym
language, and the `apple.intelligence` toolbar glyph.
