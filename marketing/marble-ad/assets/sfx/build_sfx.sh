#!/usr/bin/env bash
# Regenerates the Marble ad sound design with FFmpeg (deterministic, royalty-free —
# everything is synthesized, no samples). Outputs the individual SFX plus the final
# 30s soundtrack.wav that gets muxed onto the render by `npm run build`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# --- individual cues ---------------------------------------------------------
# Ambient pad bed (30s): soft low fifth, slow LFO movement, reverb, fades.
ffmpeg -y -f lavfi -i "sine=frequency=110:duration=30" -f lavfi -i "sine=frequency=164.81:duration=30" \
  -filter_complex "[0][1]amix=inputs=2,apulsator=hz=0.09:width=0.4,lowpass=f=600,aecho=0.8:0.6:60:0.3,afade=t=in:d=2,afade=t=out:st=27.6:d=2.4,volume=0.8" \
  -ac 2 -ar 44100 bed.wav

# Transition whoosh (~0.55s): enveloped band-passed pink noise.
ffmpeg -y -f lavfi -i "anoisesrc=d=0.55:c=pink:a=0.7" \
  -af "bandpass=f=1400:width_type=h:w=1700,afade=t=in:d=0.08,afade=t=out:st=0.2:d=0.35,volume=2.2" -ac 2 -ar 44100 whoosh.wav

# Soft impact / logo boom (~0.7s): low sine thump + click transient.
ffmpeg -y -f lavfi -i "sine=frequency=58:duration=0.7" -f lavfi -i "anoisesrc=d=0.06:c=white:a=0.5" \
  -filter_complex "[0]afade=t=out:st=0.05:d=0.65,volume=2.0[s];[1]highpass=f=1500,afade=t=out:d=0.06,volume=0.7[k];[s][k]amix=inputs=2:normalize=0" \
  -ac 2 -ar 44100 boom.wav

# CTA chime (~1.4s): A-major triad bell with decay + echo.
ffmpeg -y -f lavfi -i "sine=frequency=880:duration=1.4" -f lavfi -i "sine=frequency=1108.73:duration=1.4" -f lavfi -i "sine=frequency=1318.51:duration=1.4" \
  -filter_complex "[0][1][2]amix=inputs=3,afade=t=out:st=0.15:d=1.2,aecho=0.8:0.7:80:0.3,volume=1.3" -ac 2 -ar 44100 chime.wav

# UI "one tap" tick (~0.12s).
ffmpeg -y -f lavfi -i "sine=frequency=1100:duration=0.12" -af "afade=t=out:d=0.12,volume=0.85" -ac 2 -ar 44100 tap.wav

# --- final 30s soundtrack ----------------------------------------------------
# Bed + whooshes on each cut (0,4,9,14,20,25 → started ~0.2s early) + logo booms
# (intro / CTA) + a tap on the "one tap" line + the CTA chime. Limited to avoid clipping.
ffmpeg -y -i bed.wav -i whoosh.wav -i boom.wav -i tap.wav -i chime.wav \
 -filter_complex "[0]volume=0.55[bed];\
  [1]asplit=6[wa][wb][wc][wd][we][wf];\
  [wa]adelay=50|50,volume=0.5[w0];[wb]adelay=3800|3800,volume=0.5[w1];[wc]adelay=8800|8800,volume=0.5[w2];\
  [wd]adelay=13800|13800,volume=0.5[w3];[we]adelay=19800|19800,volume=0.5[w4];[wf]adelay=24800|24800,volume=0.5[w5];\
  [2]asplit=2[ba][bb];[ba]adelay=200|200,volume=0.55[b0];[bb]adelay=25200|25200,volume=0.55[b1];\
  [3]adelay=4500|4500,volume=0.7[t0];\
  [4]adelay=26300|26300,volume=0.55[c0];\
  [bed][w0][w1][w2][w3][w4][w5][b0][b1][t0][c0]amix=inputs=11:normalize=0:dropout_transition=0[m];\
  [m]apad,atrim=0:30,alimiter=limit=0.9,volume=1.0[out]" \
 -map "[out]" -ac 2 -ar 48000 soundtrack.wav

echo "Wrote soundtrack.wav ($(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 soundtrack.wav)s). Run 'npm run build' to mux it onto the render."
