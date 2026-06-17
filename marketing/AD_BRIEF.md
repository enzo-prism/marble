# Marble — 30-Second App Ad Brief

A HeyGen-ready spec for a 30s vertical (9:16) ad. Pair this with the captured
assets in `marketing/assets/` (screenshots + screen recordings). Everything here
reflects the **current** app — four tabs (Journal, Calendar, Supplements, Trends),
strictly monochrome. *(The old `marketing/remotion` cut is stale: it advertises the
removed Empire/Talents feature — do not reuse those scenes or shots.)*

---

## The product, in one line
**Marble** — a fast, beautiful, private workout + supplement journal. Log a set in
one tap, build the habit, and watch your strength compound. Local-only; nothing
leaves your phone.

## Tone & look
- **Brand:** pure black/white, marble-solid, disciplined. No gimmicks.
- **Mood:** calm confidence → quiet momentum. Premium, not hype.
- **Format:** 1080×1920, 30 fps, ~30s. Dark-mode shots (assets are dark).
- **Type:** heavy sans (SF Pro / Helvetica Neue), tight tracking, lots of negative space.
- **Music:** minimal, steady pulse that builds subtly; resolve on the logo.
- **Tagline (always the closer):** *Your training, set in stone.*

---

## Voiceover script (~78 words, ~28–30s, measured pace)
> Every rep you do deserves to be remembered.
> Marble logs your sets in seconds — weight, reps, rest, one tap.
> Show up… and watch the calendar fill in.
> See your strength compound — volume, PRs, every streak.
> Track your supplements right alongside your lifts.
> Plan your split. Keep it private — it all lives on your phone.
> Marble. Your training, set in stone.
> Download free on the App Store.

---

## Scene-by-scene (6 beats × ~5s)

| # | Time | Shot (asset) | On-screen text | VO line |
|---|------|--------------|----------------|---------|
| 1 | 0:00–0:04 | Logo build → `recordings/tour.mp4` @ 0:00 (Journal) | **MARBLE** · *Your training, set in stone.* | "Every rep you do deserves to be remembered." |
| 2 | 0:04–0:09 | `shots/journal.png` / `shots/addset.png` | **Log in seconds.** | "Marble logs your sets in seconds — weight, reps, rest, one tap." |
| 3 | 0:09–0:14 | `shots/calendar.png` + `recordings/tour.mp4` @ ~0:12 (day sheet) | **Build the streak.** | "Show up… and watch the calendar fill in." |
| 4 | 0:14–0:20 | `shots/trends.png` + `recordings/tour.mp4` @ ~0:24 (range change) | **Watch it compound.** | "See your strength compound — volume, PRs, every streak." |
| 5 | 0:20–0:25 | `shots/supplements.png` → `shots/split.png` | **Your whole routine.** | "Track your supplements right alongside your lifts. Plan your split. Keep it private." |
| 6 | 0:25–0:30 | Logo + CTA | **MARBLE** · *Download on the App Store* | "Marble. Your training, set in stone. Download free on the App Store." |

**Motion direction:** slow Ken-Burns push-in on each still (≈1.0→1.06 scale), gentle
float; 12-frame cross-dissolves between beats; on-screen text reveals word-by-word a
beat after the VO starts. Drop in clips from `tour.mp4` where real motion sells it (the
calendar day-sheet open, switching the Trends range).

### `recordings/tour.mp4` — what's where (60s continuous, 1260×2736, dark)
| Timecode | Screen |
|---|---|
| 0:00–0:11 | Journal — "Ready to log" hero, scrolling the day's sets + history |
| 0:11–0:22 | Calendar — month of marks, opening a logged day's sheet |
| 0:22–0:40 | Trends — consistency + volume charts, cycling the date range |
| 0:40–0:55 | Supplements — the creatine/protein streak |
| 0:55–1:00 | back to Journal |

`recordings/tour-raw.mov` is the untrimmed source (98s, includes the test-harness
launch). Regenerate with `scripts/capture_showcase_recording.sh` after a
`build-for-testing`.

---

## Shot list → assets
| Asset | Screen | Notes |
|---|---|---|
| `shots/journal.png` | Journal (populated) | Hero "Ready to log" card + today's sets |
| `shots/addset.png` | Add Set sheet | The one-tap logging moment (beat 2) |
| `shots/calendar.png` | Calendar | Month full of marked training days (beat 3) |
| `shots/trends.png` | Trends | Rising volume + consistency + PRs (beat 4) |
| `shots/supplements.png` | Supplements | Creatine/protein streak (beat 5) |
| `shots/split.png` | Split | Weekly Push/Pull/Legs plan (beat 5) |
| `recordings/tour.mp4` | live flows | 60s of real interaction (Journal → Calendar → Trends → Supplements) |

All stills are 1179×2556 (iPhone 15 Pro), dark mode, generated from the
`seedShowcase` dataset (a realistic ~6-week progressive-overload history).

---

## HeyGen Hyperframes — assembly brief
*(I can't drive Hyperframes directly; feed it this + the assets.)*
1. New project, **9:16, 30s**. Import `marketing/assets/`.
2. Lay the 6 beats above on the timeline at the listed timecodes.
3. Paste the **VO script** into the voiceover/avatar track; pick a calm, confident
   voice; let scene cuts follow the sentence breaks.
4. Drop each shot/recording into its beat; apply a slow push-in to the stills.
5. Add the on-screen text per beat (heavy sans, white, centered, word-by-word reveal).
6. Music: minimal building pulse; down-beat lands on the beat-6 logo.
7. End card: **MARBLE** wordmark + **Download on the App Store** + tagline.

## Captions / store copy (reusable)
- Hook: *"Every rep, set in stone."*
- Body: *"The fastest way to log your lifts — and actually watch them add up. Private, on-device, beautifully simple."*
- CTA: *"Marble — free on the App Store."*
