# Add Workout: text fidelity and review

## September 5, 2026 implementation

An owner Notes paste exposed a data-loss bug: two count-only drills were rejected,
and two sets of each sprint became one. Build 67 must not be treated as acceptance
of this feature. The replacement is being validated; see RELEASE_HANDOFF.md for
the current release state, not historical App Store entries elsewhere.

The regression source is:

```text
9/4/26

Straight Leg Speed Bounds (2 sets)

Knee Drive Speed Bounds (2 sets)

Resistance Rope Sprint 2 sets , 50m each

Sprints , 2 sets , 50m each
```

Expected: September 4, 2026; four exercise blocks in that order; eight sets. The
first four sets have no inferred reps, weight, distance, or duration. The last four
have distance 50 metres each and no invented reps, weight, or duration. The first
movement is not the session title. Preview and recovery create no journal entries;
confirmation saves one completed session, and replay cannot duplicate it.

## Interpretation contract

- Parse CSV and clear notation locally before invoking Apple Intelligence. If parsing
  is complete, return it directly. Otherwise try one notation rewrite, parse it
  deterministically, and validate its claims against the source. Use structured
  extraction only if that rewrite has no usable grounded content. A partial grounded
  rewrite retains unresolved source for review rather than claiming completeness.
- Treat explicit set counts as counts, including parentheses, punctuation,
  number words, count-first phrases, and per-set distance/time specifications.
- Missing metrics stay nil. A count-only exercise offers optional reps for future
  editing; it does not require the person to fabricate them. No SwiftData schema
  change is needed for these values.
- Preserve units and the relationship between each set's load and reps, including
  small kilogram loads. Bound expansion before allocating set arrays.
- Keep planned, skipped, corrected, contradictory, or unsupported text reviewable.
  A total distance does not establish a distance for every effort. Existing rep-range
  interpretation uses the lower bound, with the written range retained in notes.
- Check model claims against the movement's source span and typed metrics. Numbers
  appearing elsewhere in a workout do not justify a value. Preserve trustworthy
  deterministic blocks, their order, and repeated movements.
- Keep generated per-set array positions; never shift invalid values or repeat the
  final array element to invent missing measurements. Respect preferred weight units.

## Review and persistence

Review begins with exercise/set totals and per-exercise summaries, followed by
editable title, date, exercises, and metrics. Original input remains expandable.
Native controls and a solid action area support light/dark and Dynamic Type.
History details and Repeat preserve the saved source exercise/set order, including
repeated movements; repeating opens a review draft before any new session is saved.

Unresolved text is not disposable. The person can retry an edited line or explicitly
keep it in workout notes. Saving a single workout or selected batch blocks while
unresolved lines remain. A partially successful retry does not erase the remainder
or append duplicate partial results. Stable line IDs preserve edits when other rows
are removed. Resolved notes and review corrections participate in draft recovery.

The existing journal contract still defaults missing RPE to 8 and missing rest to
the exercise default; review identifies those defaults. They are not extracted
observations. Primary metrics remain nil when absent.

## Apple Intelligence boundaries

Availability is checked on device. Model work uses at most two fresh generation
attempts and checks cancellation between stages. A conservative 4,000 UTF-8 byte
per-session input budget reserves context for instructions, schema, and output;
oversized source falls back without truncation. CSV never goes through the model.
No cloud model, account, external workout upload, or subscription was added.

Guided generation provides a structured response, not proof that its facts are
correct. Source grounding and explicit unresolved review remain necessary. Lexical
grounding is conservative; it cannot establish universal understanding of every
language, ambiguity, or prose format. Do not claim perfect accuracy from a corpus
pass, fallback result, or simulator run.

Design decisions follow Apple's guidance on
[guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation),
[context management](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window),
[input boundaries](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output), and
[evaluation](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses).
Keep implementation within the deployed iOS 26 SDK; newer documentation may describe
beta APIs that are not available here.

## Validation

`WorkoutNotesAcceptanceTests` checks the actual note through review, JSON recovery,
save, persisted values, and deduplication. Counted-note and independent held-out
tests cover punctuation, notes, units, repeated blocks, skipped/planned activity,
total distance, correction language, and long source. Arbiter and generated-value
tests check fabricated values and array alignment independently of the model.

Run `make unit`, `make ui`, `make audit`, and normal snapshot comparisons. Intentional
layout reference changes must be recorded via `make snapshot-record` and visually
reviewed. Live Foundation Models evaluation must report direct generation separately
from the fallback pipeline. Mac model results are not iPhone acceptance.

The final local unit run (`work/workout-all-unit-v4.log`) passed **920 tests with
five skips**. The real Mac model harness passed **11/11 final pipeline cases**
with strict checks for every set, movement order/identity, stated metrics and units,
and absent metrics remaining absent. Date cases also matched the expected source
day. This is the deterministic/rewrite/conditional-extraction pipeline, not a claim
that direct structured model generation passed: earlier direct-only checks failed.
The five initially held-out cases exposed defects before correction and are now
regression cases, not an unseen final test set. See the saved analysis
`outputs/marble-workout-ai-evaluation.md` and its source-hash/evidence links in the
coordinating workspace. The harness ran on macOS 26.6.2 with Foundation Models
available; it compiles feature sources with minimal dependency stubs.

Full UI, snapshot, accessibility, migration and final-source release gates are
still in progress. No final build-68 commit or upload is established by these
results, and physical-device acceptance remains unverified.

The old aggregate live corpus threshold and first-set-only expectations are
historical diagnostics, not sufficient release evidence. Exact per-set/nil
acceptance checks and the physical-device workflow remain required.
