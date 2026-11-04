---
name: log-workout
description: Logs strength or sprint training to Marble from what the lifter says, from one set ("log bench 185 for 5") to a whole workout ("I did squats 5x5 at 225 then three sets of pull-ups").
---
Marble is a private training journal. Getting a logged number wrong is worse than
asking, because wrong sets corrupt the lifter's personal bests and trends.

## Pick the right tool

- **One set of one exercise** ("log a set of bench", "bench 185 for 5", "8 reps
  at 40 on dumbbell press"): use the log a set of an exercise tool. Reps, weight
  and unit are optional; leave out whatever the lifter didn't say and Marble copies
  it from their last set of that exercise.
- **"Same again", "another one", "repeat that set"** with no exercise named: use the
  log last set again tool.
- **Several sets, several exercises, a whole session, or anything with notation like
  "3x8" or "5x5"**: use the review workout text tool and pass the lifter's words
  through unchanged. Do not split a multi-set request into many single-set logs —
  the review screen expands set counts, matches exercises to the library, and lets
  the lifter confirm before anything is saved.
- **A pasted or shared Hevy/Strong CSV or a notes file**: use the review workout
  file tool.

## Weights and units

- Never invent a unit. Only set the unit when the lifter said "pounds", "lb",
  "kilos" or "kg". Otherwise leave it empty and Marble uses the unit that exercise
  was last logged in.
- For dumbbell exercises, the weight is **one dumbbell**. "Dumbbell press with the
  40s" means weight 40, not 80. If the lifter gives a total ("80 pounds total on
  dumbbell press"), ask which they mean before logging.
- If the lifter says a number without saying whether it's reps or weight ("log 12 on
  curls"), ask.

## Exercises

- Match the exercise to one in the lifter's Marble library. If several match ("bench"
  could be Bench Press or Incline Bench), ask which one, listing at most three.
- Don't create exercises from a single-set request. If nothing matches, offer the
  review workout text tool instead, which can add new exercises after the lifter
  reviews them.

## After logging

- Repeat back exactly what Marble said it logged. If Marble reports a new personal
  best, say so.
- If Marble says it couldn't log the set because a required number is missing, ask
  the lifter for that number and try once more. Don't guess it.
- If a workout is running, sets join it automatically; don't start a new workout to
  log a set.
