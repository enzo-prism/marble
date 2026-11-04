# Siri AI Developer Preview spike

Apple opened Siri AI to every developer on 2026-11-03 ("Siri AI is now open to all
developers", developer.apple.com/news/?id=gdk2umrf). Before that, the new Siri could only act
on apps that fit an app schema domain. There is no fitness domain, so Marble had nothing but
its fixed App Shortcut phrases. The preview lets any app expose **custom** intents
("tools") and entities, plus Markdown **app skills** that explain how they fit together.

Docs: `developer.apple.com/documentation/appintents/siri-ai-developer-preview`, and its two
articles *Bringing custom actions and content to Siri* and *Orchestrating complex actions
with app skills*.

## What is on this branch

| Change | Builds on Xcode 27.0? | Ships in a normal build? |
|---|---|---|
| `@Parameter(description:)` on every Siri-facing intent parameter | Yes | Yes — also improves Shortcuts |
| `ExerciseEntity` exposes favorite, last performed, total sets, heaviest set, most reps set and usual range as `@Property` values | Yes | Yes |
| One batched `SetEntry` fetch for entity lists (`ExerciseEntity.entities(for:in:)`) | Yes | Yes |
| `@AppIntent(.tool)` on LogSet, LogLastSetAgain, Start/FinishWorkout, ReviewWorkoutText, Extend/EndRest | **No** — needs the preview SDK | Only with `SIRI_AI_PREVIEW` |
| `@Property(description:)` on the new entity properties | **No** — needs the preview SDK | Only with `SIRI_AI_PREVIEW` |
| `Skills.skillsbundle` (`log-workout`, `run-workout-session`, `check-progress`) | Not added to the target | No — see below |

Everything preview-only sits behind the `SIRI_AI_PREVIEW` compilation condition, which is
**not** set in `project.pbxproj`. Release archives from Xcode 27.0 are unaffected.

## Building the preview variant

Needs Xcode 27.3 beta, and an Apple Intelligence device on iOS/iPadOS 27.3 beta set to a
supported language (English, French, Japanese, Korean, Portuguese, Spanish). Siri AI does
not run in the Simulator.

1. Build with the flag:
   ```bash
   xcodebuild -project marble.xcodeproj -scheme marble -destination 'generic/platform=iOS' \
     SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) SIRI_AI_PREVIEW' build
   ```
   Or add `SIRI_AI_PREVIEW` to the app target's Debug *Active Compilation Conditions* locally.
   Don't commit that.
2. Add the skills bundle: drag `SiriAIPreview/Skills.skillsbundle` into the `marble` target
   in Xcode 27.3, or create one with File › New › File from Template › Skills Bundle and copy
   the three `Skills/<name>/SKILL.md` folders in. Make sure it is in the app target's Copy
   Bundle Resources phase. It deliberately lives outside `marble/` because that group is
   filesystem-synchronized: putting it there would copy the uncompiled Markdown into every
   Xcode 27.0 build.
3. Run from Xcode on the device, or upload to **internal** TestFlight (test group A).
   The preview does not reach external testers or App Store users.
4. Run Xcode's Siri Integration Advisor and fix what it reports. The first thing to check
   is whether `@AppIntent(.tool)` coexists with the `PredictableIntent` / `UndoableIntent`
   / `LiveActivityIntent` conformances these intents already have.

## Requests to try

App in the foreground, or a rest timer Live Activity running (Siri needs no app name in
either case):

- "Log bench 185 for 5" · "same again" · "8 reps at 40 on dumbbell press" (must log 40 per
  dumbbell, not 80)
- "I did squats 5x5 at 225, then three sets of pull-ups" (must open review, not log)
- "Add 30 seconds" · "skip rest" · "I'm done"

With the app in the background (name Marble in the request):

- "What's my bench PR in Marble?" · "When did I last squat in Marble?" · "What do I usually
  curl in Marble?"

## Open questions before App Store submission (opens spring 2027)

- **Privacy copy.** Marble promises nothing leaves the device. Apple's post says Siri AI is
  at least partly server-side, so entity properties Siri reads (PRs, dates) may be processed
  by Apple. The App Store text, onboarding and `PrivacyInfo.xcprivacy` need review. Body
  metrics should stay out of Siri, or use `authenticationPolicy: .requiresAuthentication`,
  if they are ever exposed.
- **Availability.** Not in the EU on iOS, not for users under 13, daily usage limits. Siri
  must stay an extra; every flow keeps working in-app.
- Apple Intelligence group labs: Nov 4, 9–10 a.m. PT and Nov 5, 6–7 p.m. PT.

## Next steps, not started here

1. `LongRunningIntent` for `StartWorkoutIntent` with a workout-long Live Activity. The API is
   already in the iOS 27.0 SDK, and it extends the "no app name needed" window from rest
   periods to the whole workout (see the TODO in `WorkoutSessionIntents.swift`).
2. Distance and duration parameters on `LogSetIntent`, so sprints can be logged by voice.
3. A `WorkoutSessionEntity` (indexed, `Transferable`) for "what did I do last leg day?",
   "repeat Tuesday's workout" and "send my workout to my coach".
4. A `@AppEntity(.generable)` workout draft so Siri can fill multi-exercise requests
   directly, routed into the existing review screen.
5. Onscreen context on Add Set, exercise detail and session detail ("log another of this").
6. `SiriEvaluations` scripted conversations in CI for the requests above.
