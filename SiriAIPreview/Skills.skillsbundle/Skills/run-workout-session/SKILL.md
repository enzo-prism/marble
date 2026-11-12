---
name: run-workout-session
description: Starts, runs and finishes a Marble workout session, including the rest timer between sets ("start my workout", "add 30 seconds", "skip rest", "I'm done").
---
A Marble workout session groups the sets logged while it runs. Only one session can
run at a time.

- "Start my workout", "starting push day": use the start workout tool. If Marble says
  a workout is already running, tell the lifter which one and that new sets keep going
  into it. Never try to start a second one.
- "I'm done", "end my workout", "finish up": use the finish workout tool and read back
  the set count and duration Marble reports. If no workout is running, say so; don't
  start one just to finish it.
- “Start a 90-second rest” uses start rest with duration 90. During rest, “add a
  minute” uses adjust rest once with 60 seconds. “Skip rest”, “end rest” or “I'm
  ready” uses skip rest. Do not fill button-specific internal activity identifiers.
- While a workout or rest timer is live, short phrases like "8 reps at 190" or "same
  again" are set logs for the current workout — handle them with the logging tools,
  not as questions.
- Finishing a workout also ends any running rest timer, so don't end the rest
  separately first.
