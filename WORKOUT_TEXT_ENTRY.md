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

Availability, locale and the circuit breaker are checked on device first. Complete,
plausible notation (per `ModelEscalationPolicy`) skips the model entirely. The
notation rewrite runs first; structured extraction runs only when the rewrite yields
no source-grounded content. Each pass gets one fresh-session retry, and only for
transient failures (guardrail, refusal, rate limit, concurrent requests); missing
assets or unclassified errors stop model calls for 10 minutes. Cancellation is
checked between stages. A per-session UTF-8 byte budget derived from the model's
context window (`inputByteBudget(contextSize:)`: what remains after the rewrite
instructions and the 1,024-token output reserve, at 1.75 bytes per token — 3,976
bytes on iOS 26's 4,096-token model, roughly three times that on an 8K iOS 27
model), then an exact token count (iOS 26.4+), reserves room for instructions,
schema, and output; oversized source falls back without truncation. CSV never goes
through the model.
No cloud model, account, external workout upload, or subscription was added.
Nothing uses Private Cloud Compute.

### Plain-text rewrite (guardrails)

`SystemLanguageModel.Guardrails.permissiveContentTransformations` relaxes guardrails
only for text responses; guided (`@Generable`) generation keeps the default
guardrails and still threw on benign gym prose. The notation rewrite therefore
answers in plain text: an optional first line `Date: <as written>`, then one
notation line per exercise block. `ModelNotationOutput` strips bullets, numbering,
code fences, emphasis, quotes and chatter ("Here is…", "Note: …") but never edits a
line's words or numbers. The lines then go through `HandwrittenWorkoutParser`; the
date literal is kept only when the source states it (`sourceDate`); units come from
each movement's source span (`applyingSourceWeightUnits`); and the arbiter grounds
the result as before. Structured extraction (`GeneratedWorkout`) is unchanged and
remains the fallback. Prewarming still warms the rewrite instructions plus the same
prompt prefix.

### Streaming, sources and feedback (HIG Generative AI)

- The rewrite streams (`streamResponse`). Each finished notation line is reported as
  `WorkoutParseStage.partialNotation` and shown as a quiet monochrome list under the
  stage text (Paste or Type keeps its Stop button). Only complete lines are shown;
  VoiceOver is told the stage once per change, not each line. The draft is built
  from the final snapshot by the same `rewriteDraft` a non-streamed answer would
  use, so streaming changes when lines appear, not the result. A stopped or
  superseded preview ignores late progress.
- The staged `parse(ocrText:referenceDate:pageImages:onStage:)` is now a
  `WorkoutScanParsing` requirement. Before, it was only an extension method, so calls
  through `any WorkoutScanParsing` never reached the on-device parser's stages.
  Conformers must spell the closure type as `WorkoutParseStageHandler`: the app
  target builds with approachable concurrency and the test targets don't, so a
  hand-written closure type in a test file silently fails to witness the requirement.
- A model-interpreted draft carries `ParsedExerciseDraft.sourceExcerpt` (from
  `WorkoutDraftArbiter.sourceSpan`), shown in review as `From: “…”` under each
  exercise (`TextEntry.Exercise.Source.<id>` / `Scan.Exercise.Source.<id>`). It is set
  once at parse time, so it survives renaming and draft recovery; deterministic
  drafts don't get one.
- Model-interpreted reviews end with "Was this read correctly?" thumbs up/down
  (`<prefix>.ModelFeedback.Up` / `.Down`). Only aggregate counts are stored, in user
  defaults (`modelReadFeedback.correctCount` / `.incorrectCount`), once per reviewed
  workout. A thumbs-down offers a person-initiated `ShareLink`
  (`<prefix>.ModelFeedback.Share`) with their text, Marble's reading as the parse
  returned it (`ModelReadSnapshot`, frozen before any review edits) and, if they
  changed it, a "Corrected to:" section. The text is built only when the share
  sheet exports it (`ModelReadShareItem`). The snapshot is in memory only, so a
  draft restored after relaunch offers no share rather than passing corrections off
  as the reading. Nothing is sent automatically.
- Model issues come back per call (`WorkoutScanParsing.parseOutcome` →
  `WorkoutParseOutcome`), not from the parser's shared `lastModelIssue`, and both
  view models apply them only while that parse still owns the screen.
- Lines a model prefixes with filler ("Sure, Bench 3x8", "Here's the workout:
  Row 3x10") keep the notation after the first `:` `,` or `.`, but only after a
  recognized conversational opener and only when the rest starts with a name and
  has a number; commentary ("Note:", "I dropped…") is never mined.

### Availability copy

Copy branches on `SystemLanguageModel.Availability.UnavailableReason`
(`ModelAvailabilityStatus`): an ineligible iPhone is told it doesn't support Apple
Intelligence and that gym notation still works on device; `modelNotReady` says it is
still downloading; `appleIntelligenceNotEnabled` asks to turn it on only before
iOS 27 (Apple Intelligence can't be turned off on iOS 27, so iOS 27 copy never says
"turn on"). The review's model-issue note uses the same reasons.

### iOS 27 models and page images

`OnDeviceModelVersion` reports the system model (`SystemLanguageModel.Variant`
display name on iOS 27, "iOS 26 base model" before), its context size and whether it
accepts images. Debug builds record it per parse (`lastModelVersion`), and the live
eval prints it and applies per-variant thresholds (`FoundationModelsEvalThresholds`;
iOS 26's historical 0.8 / 0.7 / 0.6 is the floor, iOS 27 bars are provisional until a
device run calibrates them).

For photo scans on iOS 27, when the model's `capabilities` contain `.vision`, the
captured pages (at most three, each downscaled to 1,024 px on the long edge, with
their orientation) are attached to the rewrite prompt after the OCR text, with a note
that the OCR text is authoritative and the photo only settles layout (rows/columns,
crossed-out or checked sets, handwriting). Images are dropped — never the text — when
they don't fit the context window or the token count fails, and a rewrite that fails
with images retries once on text alone. Grounding is always against the OCR text.
Typed text, iOS 26 and models without image input behave exactly as before.

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
The deployment target is iOS 26.0: every iOS 27 symbol sits behind
`if #available(iOS 27.0, *)` (and `#if compiler(>=6.4)`), and only symbols available
in the iOS 27.0 SDK are used (CI and the archive build with Xcode 27.0), never
27.1+ additions such as `Transcript.DataAttachment`.

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

Local Notes review/timing audits passed in light/dark at default and largest text.
The largest simulator size does not support the Dynamic Type audit category;
contrast, clipping and interaction checks remain active. Native scroll-induced
footer contrast reports require an independent fully-visible re-audit before being
resolved. Full snapshots, UI, migration and exact-source GitHub checks are release
gates; these local results do not establish an uploaded or device-accepted build.

The old aggregate live corpus threshold and first-set-only expectations are
historical diagnostics, not sufficient release evidence. Exact per-set/nil
acceptance checks and the physical-device workflow remain required.
