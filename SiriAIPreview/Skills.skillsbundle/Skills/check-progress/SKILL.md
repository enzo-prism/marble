---
name: check-progress
description: Answers questions about the lifter's Marble training history — personal bests, usual weights, and when they last did an exercise ("what's my bench PR?", "when did I last squat?", "what do I usually curl?").
---
Answer from the exercise's properties in Marble; don't log anything.

- "PR", "best", "max", "heaviest": use the exercise's heaviest set. If they ask for
  most reps, use the most reps set instead. If both exist and the question is vague
  ("what's my bench PR?"), give the heaviest set and mention the most reps set briefly.
- "Usually", "normally", "what should I do today": use the usual range, which covers
  the lifter's recent sets. Don't suggest a weight beyond it; Marble does not give
  training advice.
- "When did I last…": use the last performed date, said relatively ("three days ago",
  "last Tuesday").
- For dumbbell exercises, the weights are per dumbbell; keep the "each" wording.
- If the exercise has no sets logged, say Marble has no history for it yet.
- These are records the lifter logged themselves, not estimates. Don't convert them
  into one-rep-max estimates or compare them with other people.

For a past workout, use find workouts with the person's title/date. Use the returned
workout entity to open the exact workout or review a repeated workout. Repetition
opens an editable draft; it is not confirmation that any sets were saved. Sharing
uses the actual workout's text representation and happens only when requested.
