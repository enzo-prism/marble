# Siri AI developer preview

Verified against Apple's documentation on November 11, 2026. Marble's public
configuration builds with stable Xcode 27.0 and deploys to iOS 26. Preview custom
tools require Xcode/iOS 27.3 and supported Apple Intelligence hardware.

Apple makes this preview available to development-signed installations and internal
TestFlight testers. External TestFlight and App Store installations do not receive
it. Do not describe these experimental capabilities as a public shipped feature.

Sources:
- [Preview availability](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview)
- [Custom tools and entities](https://developer.apple.com/documentation/appintents/bringing-custom-actions-and-content-to-siri)
- [Compiled app skills](https://developer.apple.com/documentation/appintents/orchestrating-complex-actions-with-app-skills)
- [Siri evaluations](https://developer.apple.com/documentation/sirievaluations)
- [App Intents system-path testing](https://developer.apple.com/documentation/appintentstesting)

## Normal configuration

The release configuration does not define `SIRI_AI_PREVIEW` or include the skills
bundle. The normal App Intents expose complete set metrics, typed confirmed sets,
precise duration, corrections by stable set ID, actual workout lookup/open/repeat
review, and rest start/adjust/skip. Successful live logging shares persistence,
session attachment and rest policy with the UI. Repetition preserves sprint detail.

A workout-long ActivityKit card represents the real journal workout. Optional
HealthKit tracking owns genuine live sensor collection. `LongRunningIntent` is for
active computational work with progress; it is not a workout lifecycle mechanism.

## Reproducible development configuration

`build_preview.rb` creates an ignored `.MarbleSiriPreview.xcodeproj` alongside the
normal project. It enables preview annotations only in Debug, adds exactly one
skills bundle to the app resources, validates Apple's restricted skill format,
and requires build-log evidence of skill compilation. It refuses Xcode/SDKs older
than 27.3 and does not archive, upload or submit a public binary.

With a supported Xcode selected and a physical iOS 27.3+ device:

```sh
BUNDLE_GEMFILE=SiriAIPreview/Gemfile bundle install
BUNDLE_GEMFILE=SiriAIPreview/Gemfile bundle exec ruby SiriAIPreview/build_preview.rb \
  DEVICE_UDID /absolute/path/to/preview-derived-data \
  CODE_SIGN_STYLE=Manual \
  MARBLE_BUNDLE_SUFFIX=.validation \
  MARBLE_DEVELOPMENT_PROFILE='Marble Validation Development 2026-11-11' \
  MARBLE_WIDGET_DEVELOPMENT_PROFILE='Marble Validation Widgets Development 2026-11-11' \
  MARBLE_SHARE_DEVELOPMENT_PROFILE='Marble Validation Share Development 2026-11-11' \
  MARBLE_WATCH_DEVELOPMENT_PROFILE='Marble Validation Watch Development 2026-11-11'
```

Use the matching profiles for the actual device. Check the generated project's
resource type in Xcode if a changed beta no longer recognizes the bundle. A raw
copy of SKILL.md files is not evidence that Apple compiled or indexed app skills.

## Acceptance

`conversations.json` specifies the conversational corpus and exact data assertions.
It is scenario data, not a completed SiriEvaluations run. The installed Xcode 27.0
has no SiriEvaluations framework and the connected iPhone runs iOS 27.2, so preview
compilation, Integration Advisor, generable draft/card APIs, and scripted Siri
conversations remain unverified. Do not infer acceptance from normal compilation.

Before enabling the preview for internal distribution:

1. Build with the actual 27.3 SDK and verify compiled skills in the resulting app.
2. Run Integration Advisor, including tool conformance interactions with
   `PredictableIntent`, `UndoableIntent` and `LiveActivityIntent`.
3. Implement/run the scenario corpus through the installed beta's SiriEvaluations
   API. Check the saved journal after every turn, including failure/ambiguity cases.
4. Run each scenario repeatedly, with the app foregrounded, backgrounded with its
   name in the request, and with its workout Live Activity active.
5. Verify explicit authentication, unit conversion, tenths precision, corrections,
   deleted entities, and zero writes before a bulk workout's editable review.
6. Review privacy wording: on-device workout parsing and dictation are local;
   Siri is an Apple system service and may process the exposed data using Apple's
   infrastructure. Avoid extending Marble's local-processing promise to Siri.

App skills guide selection and conversation. Bounds, persistence, stable identity,
unit conversion and review requirements belong in code and tests.
