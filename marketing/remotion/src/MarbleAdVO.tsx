import React from "react";
import {
  AbsoluteFill,
  Img,
  Sequence,
  staticFile,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

/**
 * Marble — narrated ad (≈29s / 9:16), scenes timed to the supplied voiceover SRT.
 *
 * The VO sells Marble as a clean, AI-first, no-clutter tracker that works offline (log fast,
 * splits, trends, PRs) — it never mentions the Empire/gamification, so this cut deliberately omits
 * it. On-screen text is short keyword captions that *reinforce* the narration at its timings (not
 * duplicate full sentences), so the spoken track can be laid over in production.
 *
 * Cue → frame map (30fps):
 *   1  0.08–4.53  hook            frames   0–136
 *   2  4.53–10.08 clean/AI-first  frames 136–303
 *   3 10.08–15.20 log/splits/trends montage 303–456
 *   4 15.20–20.00 PRs / no clutter         456–600
 *   5 20.40–24.68 works offline           600–740
 *   6 24.68–28.55 Train·Log·Evolve + CTA  740–870
 */

const GOLD = "#E8B24A";
const TEXT = "#F5F2EA";
const MUTED = "rgba(245,242,234,0.6)";
const FONT = '-apple-system, system-ui, "Helvetica Neue", Arial, sans-serif';

const PHONE_W = 588;
const PAD = 13;
const IMG_ASPECT = 2556 / 1179;
const INNER_W = PHONE_W - PAD * 2;
const INNER_H = INNER_W * IMG_ASPECT;
const PHONE_H = INNER_H + PAD * 2;
const PHONE_CENTER_Y = 1215;

// ----------------------------------------------------------------- background (clean / minimal)
const CleanBackground: React.FC = () => {
  const f = useCurrentFrame();
  const gx = 50 + Math.sin(f / 140) * 5;
  const gy = 40 + Math.cos(f / 170) * 4;
  return (
    <AbsoluteFill style={{ backgroundColor: "#07070A" }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(58% 42% at ${gx}% ${gy}%, rgba(232,178,74,0.10), transparent 64%)`,
        }}
      />
      <AbsoluteFill
        style={{ background: "radial-gradient(80% 55% at 50% 118%, rgba(110,128,160,0.10), transparent 60%)" }}
      />
      <AbsoluteFill style={{ boxShadow: "inset 0 0 440px 100px rgba(0,0,0,0.8)" }} />
    </AbsoluteFill>
  );
};

// ----------------------------------------------------------------- columns wordmark motif
const Columns: React.FC<{ progress: number; size?: number }> = ({ progress, size = 1 }) => (
  <div style={{ display: "flex", gap: 12 * size, justifyContent: "center", alignItems: "flex-end", height: 110 * size }}>
    {[0, 1, 2].map((i) => {
      const h = interpolate(progress, [0, 1], [0, [80, 108, 80][i] * size], { extrapolateRight: "clamp" });
      return (
        <div
          key={i}
          style={{
            width: 23 * size,
            height: h,
            borderRadius: 8 * size,
            background: `linear-gradient(180deg, ${GOLD}, #b9842b)`,
            boxShadow: "0 0 24px rgba(232,178,74,0.45)",
          }}
        />
      );
    })}
  </div>
);

// ----------------------------------------------------------------- phone
const screenImg = (src: string, zoom: number, focus: number, opacity: number) => {
  const imgW = INNER_W * zoom;
  const imgH = imgW * IMG_ASPECT;
  const left = (INNER_W - imgW) / 2;
  let top = INNER_H / 2 - focus * imgH;
  top = Math.max(INNER_H - imgH, Math.min(0, top));
  return (
    <Img
      key={src + focus}
      src={staticFile(src)}
      style={{ position: "absolute", width: imgW, height: imgH, left, top, opacity }}
    />
  );
};

const Phone: React.FC<{ duration: number; slideIn?: boolean; glow?: number; children: React.ReactNode }> = ({
  duration,
  slideIn = true,
  glow = 0,
  children,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 200, mass: 0.7 } });
  const enterY = slideIn ? interpolate(enter, [0, 1], [120, 0]) : 0;
  const enterScale = interpolate(enter, [0, 1], [slideIn ? 0.93 : 0.98, 1]);
  const float = Math.sin(frame / 34) * 6;
  const inO = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: "clamp" });
  const outO = interpolate(frame, [duration - 11, duration], [1, 0], { extrapolateLeft: "clamp" });
  return (
    <div
      style={{
        position: "absolute",
        width: PHONE_W,
        height: PHONE_H,
        left: (1080 - PHONE_W) / 2,
        top: PHONE_CENTER_Y - PHONE_H / 2,
        transform: `translateY(${enterY + float}px) scale(${enterScale})`,
        opacity: Math.min(inO, outO),
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 56,
          background: "#161618",
          border: "1px solid rgba(255,255,255,0.10)",
          boxShadow: `0 42px 124px rgba(0,0,0,0.7)${glow ? `, 0 0 ${glow}px rgba(232,178,74,0.32)` : ""}`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: PAD,
          top: PAD,
          width: INNER_W,
          height: INNER_H,
          borderRadius: 45,
          overflow: "hidden",
          background: "#000",
          border: "1px solid rgba(255,255,255,0.06)",
        }}
      >
        {children}
        <AbsoluteFill style={{ background: "linear-gradient(135deg, rgba(255,255,255,0.10), transparent 38%)" }} />
      </div>
    </div>
  );
};

// ----------------------------------------------------------------- caption (top text)
const Caption: React.FC<{ kicker?: string; word: string; sub?: string; appear: number; size?: number }> = ({
  kicker,
  word,
  sub,
  appear,
  size = 60,
}) => {
  const y = interpolate(appear, [0, 1], [26, 0]);
  return (
    <div style={{ position: "absolute", top: 150, left: 70, right: 70, textAlign: "center", opacity: appear, transform: `translateY(${y}px)` }}>
      {kicker ? (
        <div style={{ fontFamily: FONT, fontSize: 26, fontWeight: 700, letterSpacing: 4, color: GOLD, marginBottom: 14 }}>
          {kicker}
        </div>
      ) : null}
      <div style={{ fontFamily: FONT, fontSize: size, fontWeight: 800, letterSpacing: -1.2, lineHeight: 1.05, color: TEXT }}>
        {word}
      </div>
      {sub ? (
        <div style={{ fontFamily: FONT, fontSize: 29, fontWeight: 500, color: MUTED, marginTop: 18, lineHeight: 1.3 }}>{sub}</div>
      ) : null}
      <div style={{ width: 64, height: 4, borderRadius: 2, background: GOLD, margin: "22px auto 0", opacity: 0.9 }} />
    </div>
  );
};

// ----------------------------------------------------------------- scenes
const Hook: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const l1 = spring({ frame: frame - 4, fps, config: { damping: 200, mass: 0.6 } });
  const l2 = spring({ frame: frame - 34, fps, config: { damping: 200, mass: 0.6 } });
  const out = interpolate(frame, [duration - 14, duration], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity: out }}>
      <div style={{ fontFamily: FONT, fontSize: 26, fontWeight: 700, letterSpacing: 5, color: GOLD, opacity: l1, marginBottom: 26 }}>
        GYM&nbsp;&nbsp;APP&nbsp;&nbsp;PICK
      </div>
      <div style={{ fontFamily: FONT, fontSize: 92, fontWeight: 800, color: TEXT, transform: `translateY(${interpolate(l1, [0, 1], [34, 0])}px)`, opacity: l1 }}>
        Lifting?
      </div>
      <div
        style={{
          fontFamily: FONT,
          fontSize: 56,
          fontWeight: 700,
          color: MUTED,
          marginTop: 18,
          transform: `translateY(${interpolate(l2, [0, 1], [30, 0])}px)`,
          opacity: l2,
          textAlign: "center",
        }}
      >
        Trying to stay consistent?
      </div>
    </AbsoluteFill>
  );
};

const Brand: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const cols = spring({ frame: frame - 2, fps, config: { damping: 200 } });
  const mark = spring({ frame: frame - 8, fps, config: { damping: 200, mass: 0.6 } });
  const sub = interpolate(frame, [22, 40], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const zoom = interpolate(frame, [0, duration], [1.06, 1.0]);
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", top: 120, left: 0, right: 0, display: "flex", flexDirection: "column", alignItems: "center" }}>
        <Columns progress={cols} size={0.62} />
        <div
          style={{
            fontFamily: FONT,
            fontSize: 96,
            fontWeight: 800,
            letterSpacing: 5,
            color: TEXT,
            marginTop: 16,
            transform: `translateY(${interpolate(mark, [0, 1], [28, 0])}px)`,
            opacity: mark,
          }}
        >
          MARBLE
        </div>
        <div style={{ fontFamily: FONT, fontSize: 31, fontWeight: 600, color: GOLD, marginTop: 8, opacity: sub, letterSpacing: 1 }}>
          Clean. AI-first. No clutter.
        </div>
        <div style={{ fontFamily: FONT, fontSize: 27, fontWeight: 500, color: MUTED, marginTop: 6, opacity: sub }}>
          A workout tracker for people who actually train.
        </div>
      </div>
      <Phone duration={duration} slideIn>
        {screenImg("shots/journal.png", zoom, 0.4, 1)}
      </Phone>
    </AbsoluteFill>
  );
};

type Beat = { start: number; end: number; src: string; word: string; kicker: string; focus: number };

const Montage: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const beats: Beat[] = [
    { start: 0, end: 51, src: "shots/quicklog.png", word: "Log lifts fast", kicker: "FAST LOGGING", focus: 0.34 },
    { start: 51, end: 102, src: "shots/split.png", word: "Track your splits", kicker: "SPLITS", focus: 0.4 },
    { start: 102, end: 153, src: "shots/trends.png", word: "See your trends", kicker: "TRENDS", focus: 0.52 },
    { start: 153, end: 225, src: "shots/trends.png", word: "Follow your PRs", kicker: "PERSONAL RECORDS", focus: 0.3 },
    { start: 225, end: 297, src: "shots/journal.png", word: "No ads. No clutter.", kicker: "ALL SIGNAL", focus: 0.42 },
  ];
  const fade = (b: Beat) => {
    const fin = interpolate(frame, [b.start, b.start + 9], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
    const fout = interpolate(frame, [b.end - 9, b.end], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
    return Math.min(fin, fout);
  };
  const globalZoom = interpolate(frame, [0, duration], [1.04, 1.1]);
  return (
    <AbsoluteFill>
      {beats.map((b) => {
        const a = fade(b);
        return a > 0.01 ? (
          <Caption key={b.word} kicker={b.kicker} word={b.word} appear={a} size={58} />
        ) : null;
      })}
      <Phone duration={duration} slideIn={false}>
        {beats.map((b) => screenImg(b.src, globalZoom, b.focus, fade(b)))}
      </Phone>
    </AbsoluteFill>
  );
};

const WifiOff: React.FC = () => (
  <svg width={70} height={70} viewBox="0 0 100 100" fill="none">
    <path d="M16 42 Q50 8 84 42" stroke={GOLD} strokeWidth={7} strokeLinecap="round" opacity={0.85} />
    <path d="M30 56 Q50 34 70 56" stroke={GOLD} strokeWidth={7} strokeLinecap="round" />
    <circle cx={50} cy={72} r={5} fill={GOLD} />
    <line x1={16} y1={18} x2={84} y2={86} stroke="#0b0b0e" strokeWidth={15} strokeLinecap="round" />
    <line x1={16} y1={18} x2={84} y2={86} stroke={GOLD} strokeWidth={7} strokeLinecap="round" />
  </svg>
);

const Offline: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const appear = interpolate(frame, [0, 14], [0, 1], { extrapolateRight: "clamp" });
  const badge = spring({ frame: frame - 20, fps, config: { damping: 170, mass: 0.7 } });
  const zoom = interpolate(frame, [0, duration], [1.08, 1.0]);
  return (
    <AbsoluteFill>
      <Caption kicker="THE BEST PART" word="Works offline" sub="Log mid-workout — no signal required." appear={appear} size={62} />
      <Phone duration={duration} slideIn glow={64}>
        {screenImg("shots/addset.png", zoom, 0.36, 1)}
      </Phone>
      {/* offline badge floating on the phone */}
      <div
        style={{
          position: "absolute",
          top: PHONE_CENTER_Y - 70,
          left: 0,
          right: 0,
          display: "flex",
          justifyContent: "center",
          transform: `scale(${interpolate(badge, [0, 1], [0.7, 1])})`,
          opacity: badge,
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 18,
            padding: "20px 30px",
            borderRadius: 26,
            background: "rgba(12,12,16,0.82)",
            border: `1px solid ${GOLD}`,
            boxShadow: "0 0 50px rgba(232,178,74,0.4)",
            backdropFilter: "blur(8px)",
          }}
        >
          <WifiOff />
          <div style={{ fontFamily: FONT, fontSize: 40, fontWeight: 800, color: TEXT, letterSpacing: 1 }}>OFFLINE</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const CTA: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const inO = interpolate(frame, [0, 14], [0, 1], { extrapolateRight: "clamp" });
  const words = ["Train.", "Log.", "Evolve."];
  const btn = spring({ frame: frame - 30, fps, config: { damping: 180, mass: 0.7 } });
  const pulse = 1 + Math.sin(frame / 12) * 0.02;
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity: inO }}>
      <Columns progress={spring({ frame: frame - 2, fps, config: { damping: 200 } })} size={0.66} />
      <div style={{ display: "flex", gap: 22, marginTop: 30 }}>
        {words.map((w, i) => {
          const s = spring({ frame: frame - 8 - i * 7, fps, config: { damping: 200, mass: 0.6 } });
          return (
            <span
              key={w}
              style={{
                fontFamily: FONT,
                fontSize: 76,
                fontWeight: 800,
                color: i === 2 ? GOLD : TEXT,
                transform: `translateY(${interpolate(s, [0, 1], [30, 0])}px)`,
                opacity: s,
              }}
            >
              {w}
            </span>
          );
        })}
      </div>
      <div style={{ fontFamily: FONT, fontSize: 30, color: MUTED, marginTop: 22, opacity: interpolate(frame, [24, 40], [0, 1], { extrapolateRight: "clamp" }) }}>
        MARBLE — for people who actually train.
      </div>
      <div style={{ marginTop: 52, transform: `scale(${interpolate(btn, [0, 1], [0.82, 1]) * pulse})`, opacity: btn }}>
        <div
          style={{
            padding: "26px 54px",
            borderRadius: 50,
            background: `linear-gradient(180deg, ${GOLD}, #c2902f)`,
            color: "#1a1206",
            fontFamily: FONT,
            fontSize: 37,
            fontWeight: 800,
            boxShadow: "0 0 64px rgba(232,178,74,0.5)",
          }}
        >
          Download on the App Store
        </div>
      </div>
    </AbsoluteFill>
  );
};

const ProgressBar: React.FC = () => {
  const f = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const w = interpolate(f, [0, durationInFrames], [0, 1080], { extrapolateRight: "clamp" });
  return <div style={{ position: "absolute", bottom: 0, left: 0, height: 5, width: w, background: `linear-gradient(90deg, rgba(232,178,74,0.35), ${GOLD})` }} />;
};

// ----------------------------------------------------------------- composition
export const MarbleAdVO: React.FC = () => {
  return (
    <AbsoluteFill style={{ fontFamily: FONT, backgroundColor: "#07070A" }}>
      <CleanBackground />
      <Sequence from={0} durationInFrames={136}>
        <Hook duration={136} />
      </Sequence>
      <Sequence from={136} durationInFrames={167}>
        <Brand duration={167} />
      </Sequence>
      <Sequence from={303} durationInFrames={297}>
        <Montage duration={297} />
      </Sequence>
      <Sequence from={600} durationInFrames={140}>
        <Offline duration={140} />
      </Sequence>
      <Sequence from={740} durationInFrames={130}>
        <CTA duration={130} />
      </Sequence>
      <ProgressBar />
    </AbsoluteFill>
  );
};
