# Marble song-synced ad plan

- Source: uploaded `drake_-_time_flies_slowed_reverb_-_Chovies_192k---1e940348-bbf4-44bf-bc4f-dfb94466ddbf.mp3`.
- Selected segment: starts at `52.407s`, duration `31.25s`.
- Tempo grid: about `76.8 BPM`, `0.78125s` per beat.
- Edit rhythm: five 8-beat phrases, with scene changes at `6.25s`, `12.5s`, `18.75s`, and `25.0s`.
- Creative reason: the original 16s cut was too fast for the amount of text. This cut reduces copy and gives each app idea a full phrase to breathe.
- Audio-reactive layer: `assets/music/marble-audio-data.js` precomputes per-frame amplitude, bass, mids, highs, beat pulses, and offbeat pulses. HyperFrames reads that data inside the paused GSAP timeline so glow, sheen, rails, veins, and device highlights react deterministically.
