# frames.md — Marble 30s App Ad (HyperFrames)

The design system + frame-by-frame plan that `index.html` implements. Source of truth
for tokens, scene windows, copy, and motion. Render: `npm run render -- --output out/marble-ad.mp4`.

## Format
- **1080×1920** (9:16 vertical), **30 fps**, **30 s** (900 frames), composition id `main`.
- All hard cuts (no shaders). Scene windows tile end-to-end with no gaps.

## Brand tokens (`:root`)
| Token | Value | Use |
|---|---|---|
| `--bg` | `#070709` | near-black stage |
| `--ink` | `#F4F2EC` | marble-white text |
| `--muted` | `rgba(244,242,236,0.56)` | sub-copy |
| `--stone` | `#C8CCD2` | cool marble highlight (the only "accent" — brand is monochrome) |
| `--line` | `rgba(244,242,236,0.14)` | hairlines |
| font | SF Pro Display / system | display **800**, sub **300** (dramatic weight contrast) |

**Monochrome on purpose.** Marble's whole identity is pure black/white — no colour pop
(the gold in the old cut belonged to the removed Empire feature). Contrast comes from
weight, scale, and a cool stone sheen on the wordmark/CTA.

## Scenes (6 × ~5s)
| # | Window | Shot / element | Headline | Sub | Motion |
|---|--------|----------------|----------|-----|--------|
| 1 | 0.0–4.0 | marble monolith + wordmark | **MARBLE** | *Your training, set in stone.* | monolith rises + sheen sweep; letters stagger |
| 2 | 4.0–9.0 | `addset.png` | Log every set in seconds. | Weight, reps, rest — one tap. | phone rise, Ken-Burns in, float |
| 3 | 9.0–14.0 | `calendar.png` | Show up. Build the streak. | Every session, marked. | Ken-Burns down, float |
| 4 | 14.0–20.0 | `trends.png` | Watch your strength compound. | Volume, PRs, consistency. | Ken-Burns push on the charts, headline sweep |
| 5 | 20.0–25.0 | `supplements.png` | Your whole routine. | Lifts + supplements. Private, on-device. | Ken-Burns, float |
| 6 | 25.0–30.0 | David app-icon + CTA pill | **MARBLE** · #1 fitness tracking app in the universe | Download on the App Store | icon reforms, button pop + breathe |

Persistent layers (track 0 / top): drifting stone glow + CSS grain + vignette;
a thin progress bar fills 0→1080 across the full 30 s.

## Motion rules (per HyperFrames agent guide)
- Entrances use `tl.from()`, offset +0.1–0.3 s into each scene (no jump-cuts).
- Every scene > 4 s has ≥1 continuous activity (Ken-Burns `scale 1→1.07 ease none`, phone float `yoyo repeat:1`).
- ≥3 eases per scene: `power3.out`, `power2.out`, `sine.inOut`, `none`.
- Non-anchor scenes: inline `visibility:hidden` + `tl.set(autoAlpha:1)` at start, `tl.set(autoAlpha:0)` at end.
- Deterministic only: no `Math.random()`, `Date.now()`, timeouts, or `repeat:-1`.

## Sound design (`assets/sfx/`)
All cues are synthesized with FFmpeg (deterministic, royalty-free — no samples). Regenerate
with `npm run sfx`. The final 30s `soundtrack.wav`:
| Cue | Time(s) | Sound |
|---|---|---|
| ambient bed | 0–30 | soft low fifth pad, slow LFO, reverb, fades in/out |
| whoosh ×6 | 0.05, 3.8, 8.8, 13.8, 19.8, 24.8 | band-passed noise swish on each scene cut |
| boom ×2 | 0.2, 25.2 | low impact on the David logo reveal (intro + CTA) |
| tap | 4.5 | UI tick under the "one tap" line |
| chime | 26.3 | A-major bell on the CTA |

**Build note:** the current HyperFrames renderer truncates long in-engine `<audio>` (~20s),
so the soundtrack is muxed onto the render with FFmpeg. `npm run build` does render → mux →
`out/marble-ad.mp4` (full 30s audio, peak ≈ −9 dB, no clipping).

## Voiceover (optional, ~28 s — add as `<audio>` track if voiced)
> Every rep deserves to be remembered. Marble logs your sets in seconds — weight, reps,
> rest, one tap. Show up, and watch the calendar fill in. See your strength compound.
> Track your whole routine, private and on-device. Marble — your training, set in stone.
