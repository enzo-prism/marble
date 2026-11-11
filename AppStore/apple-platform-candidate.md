# Apple platform candidate — distribution copy

Draft for the next verified binary. This file is not an upload receipt or evidence of
App Review submission. Select the version/build only after fresh ASC readback and the
release gates. The pre-existing approved 2.7 (86) does not contain these changes.

## What's New draft

- Log complete strength, distance and timed sets with Siri and Shortcuts, including sprint times to a tenth of a second.
- Keep your current workout and rest timer together in a Live Activity.
- Find and open specific workouts, review a workout before repeating it, or prepare a text summary to share.
- Dictate a workout on compatible devices, then edit and review the transcript before saving.
- Send workout text, supported files or images into Marble from the share sheet for review.
- Control your iPhone workout from Apple Watch: start, repeat the last confirmed set, rest, skip rest and finish.
- Optionally track a live strength workout in Apple Health. Historical exports avoid inferred session effort ratings.
- More faithful reading of explicit rep ladders and weight lists.
- Clearer Progress Details with colored charts, metric cues, readable category values and accessible legends.

## What to Test draft

Use the final source/build identified by the upload receipt. Keep the existing 2.7
import acceptance examples in `testflight/2.7-candidate.md` as regression coverage.

1. Start a workout, log a specified strength set, and repeat it through Shortcuts.
   Both sets must appear in the same running workout, with the correct units and rest.
2. Log a 50 m sprint in 7.4 seconds. Check the actual performance in the journal,
   then undo it. No previous sprint time should be supplied as a new measurement.
3. Open a past session from a system result. Repeat should open editable review;
   cancellation must leave the journal unchanged. Share should prepare that session's text.
4. During a workout, check the Lock Screen and return to Marble. Rest and the running
   session should agree after backgrounding and relaunch. Finish once.
5. Use Add → Dictate Workout. Grant microphone/speech access, speak a short workout,
   stop, edit the transcript, and review it. Cancel should discard the proposed text.
6. From Notes/Files/Photos, share supported workout content to Marble. Confirm it
   appears once in review, survives app relaunch, and writes no sets before acceptance.
7. With a paired Apple Watch and Marble open on iPhone, start, log the first set on
   iPhone, repeat once on Watch, rest, skip rest and finish. Check both set count and
   phone history. Disconnect, reconnect and retry: a lost confirmation must not duplicate a set.
8. Optionally enable Settings → Apple Health → Track live strength workouts in Apple Health.
   Authorize access, start/pause/resume/finish a workout and check one Health workout.
   Turning Health off must leave ordinary logging usable. Heart rate needs an available sensor.
9. Paste explicit lists such as `Shoulder Press 4 sets 12 10 8 8 at 50 55 60 60`.
   Every set must retain its own reps/load. A mismatched list must stay unresolved.
10. Check VoiceOver, light/dark appearance and the largest text sizes on the changed screens.
11. In Progress → Details, compare the colored metrics, weekly volume series and category
    bars. Check light/dark and Increase Contrast. Labels, symbols and exact values must
    remain readable with Differentiate Without Color and the largest text size.

## App Review notes draft

No account or login is required. Core training records remain local. Speech capture
uses Apple's on-device speech APIs and requires permission. Shared content is held in
an access-group keychain inbox for user review; sharing does not automatically commit
workouts. Health integration is optional and permission-based.

The Watch app is an iPhone-connected controller. It does not independently collect
wrist heart rate or own a Watch HealthKit workout. The iPhone live workout uses
strength training with an unspecified location. Historical exports use Other when the
record lacks an activity classification and do not derive session effort from set difficulty.

Custom Siri AI developer-preview skills are excluded from the public archive. Public
features here use the regular App Intents/Shortcuts APIs. Do not advertise the 27.3
preview conversations as an App Store capability.
