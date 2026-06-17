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
 * Marble — 35s / 9:16 app ad.
 *
 * A persistent animated background (whose warmth peaks during the colourful Empire scenes) sits
 * behind seven cross-fading scenes. Real app screenshots float in a phone mockup with cinematic
 * Ken-Burns motion; headlines reveal word-by-word. On brand: deep near-black, mostly restrained,
 * with gold (the Empire "Golden Age" accent) as the one pop of colour.
 */

const GOLD = "#E8B24A";
const TEXT = "#F5F2EA";
const MUTED = "rgba(245,242,234,0.62)";
const FONT = '-apple-system, system-ui, "Helvetica Neue", Arial, sans-serif';

// ---- Phone geometry (inner area matches the screenshot aspect exactly, so shots fit perfectly) ----
const PHONE_W = 600;
const PAD = 14;
const IMG_ASPECT = 2556 / 1179; // height / width of the source screenshots
const INNER_W = PHONE_W - PAD * 2;
const INNER_H = INNER_W * IMG_ASPECT;
const PHONE_H = INNER_H + PAD * 2;
const PHONE_CENTER_Y = 1205;

// ----------------------------------------------------------------------------- Background
const Particles: React.FC<{ warmth: number }> = ({ warmth }) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill>
      {Array.from({ length: 26 }, (_, i) => {
        const s = Math.abs(Math.sin(i * 12.9898) * 43758.5453) % 1;
        const x = Math.abs(Math.sin(i * 3.1)) * 1080;
        const base = Math.abs(Math.cos(i * 1.7)) * 1920;
        let y = (base - f * (0.4 + s * 0.9)) % 1920;
        if (y < 0) y += 1920;
        const tw = 0.3 + 0.7 * Math.abs(Math.sin(f / 22 + i));
        const size = 2 + s * 3;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: x,
              top: y,
              width: size,
              height: size,
              borderRadius: size,
              background: GOLD,
              opacity: tw * warmth * 1.7,
              filter: "blur(0.4px)",
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

const Background: React.FC = () => {
  const f = useCurrentFrame();
  // Warmth ramps up across the two Empire scenes (frames ~570–930) and settles for the CTA.
  const warmth = interpolate(f, [430, 600, 930, 985], [0.06, 0.4, 0.4, 0.12], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const gx = 50 + Math.sin(f / 120) * 6;
  const gy = 42 + Math.cos(f / 150) * 5;
  return (
    <AbsoluteFill style={{ backgroundColor: "#07070A" }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(54% 38% at ${gx}% ${gy}%, rgba(232,178,74,${warmth}), transparent 66%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(75% 55% at 50% 116%, rgba(110,130,165,0.10), transparent 60%)",
        }}
      />
      <Particles warmth={warmth} />
      <AbsoluteFill style={{ boxShadow: "inset 0 0 420px 90px rgba(0,0,0,0.78)" }} />
    </AbsoluteFill>
  );
};

// ----------------------------------------------------------------------------- Marble columns motif
const Columns: React.FC<{ progress: number }> = ({ progress }) => (
  <div style={{ display: "flex", gap: 14, justifyContent: "center", alignItems: "flex-end", height: 124 }}>
    {[0, 1, 2].map((i) => {
      const target = [92, 124, 92][i];
      const h = interpolate(progress, [0, 1], [0, target], { extrapolateRight: "clamp" });
      return (
        <div
          key={i}
          style={{
            width: 26,
            height: h,
            borderRadius: 9,
            background: `linear-gradient(180deg, ${GOLD}, #b9842b)`,
            boxShadow: "0 0 26px rgba(232,178,74,0.45)",
          }}
        />
      );
    })}
  </div>
);

// ----------------------------------------------------------------------------- Phone with Ken Burns
const PhoneShot: React.FC<{
  src: string;
  duration: number;
  zoomFrom: number;
  zoomTo: number;
  focusFrom: number;
  focusTo: number;
  glow?: number;
}> = ({ src, duration, zoomFrom, zoomTo, focusFrom, focusTo, glow = 0 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const enter = spring({ frame, fps, config: { damping: 200, mass: 0.7 } });
  const enterY = interpolate(enter, [0, 1], [120, 0]);
  const enterScale = interpolate(enter, [0, 1], [0.93, 1]);
  const floatY = Math.sin(frame / 33) * 7;

  const inO = interpolate(frame, [0, 14], [0, 1], { extrapolateRight: "clamp" });
  const outO = interpolate(frame, [duration - 12, duration], [1, 0], { extrapolateLeft: "clamp" });
  const opacity = Math.min(inO, outO);

  const p = interpolate(frame, [0, duration], [0, 1], { extrapolateRight: "clamp" });
  const zoom = interpolate(p, [0, 1], [zoomFrom, zoomTo]);
  const focus = interpolate(p, [0, 1], [focusFrom, focusTo]);

  const imgW = INNER_W * zoom;
  const imgH = imgW * IMG_ASPECT;
  const left = (INNER_W - imgW) / 2;
  let top = INNER_H / 2 - focus * imgH;
  top = Math.max(INNER_H - imgH, Math.min(0, top));

  return (
    <div
      style={{
        position: "absolute",
        width: PHONE_W,
        height: PHONE_H,
        left: (1080 - PHONE_W) / 2,
        top: PHONE_CENTER_Y - PHONE_H / 2,
        transform: `translateY(${enterY + floatY}px) scale(${enterScale})`,
        opacity,
      }}
    >
      {/* device body */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 58,
          background: "#161618",
          border: "1px solid rgba(255,255,255,0.10)",
          boxShadow: `0 44px 130px rgba(0,0,0,0.7)${glow ? `, 0 0 ${glow}px rgba(232,178,74,0.38)` : ""}`,
        }}
      />
      {/* screen */}
      <div
        style={{
          position: "absolute",
          left: PAD,
          top: PAD,
          width: INNER_W,
          height: INNER_H,
          borderRadius: 46,
          overflow: "hidden",
          background: "#000",
          border: "1px solid rgba(255,255,255,0.06)",
        }}
      >
        <Img src={staticFile(src)} style={{ position: "absolute", width: imgW, height: imgH, left, top }} />
        {/* glass sheen */}
        <AbsoluteFill
          style={{
            background: "linear-gradient(135deg, rgba(255,255,255,0.12), transparent 38%)",
          }}
        />
      </div>
    </div>
  );
};

// ----------------------------------------------------------------------------- Headline
const Headline: React.FC<{ text: string; sub?: string; accentWord?: string; duration: number }> = ({
  text,
  sub,
  accentWord,
  duration,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const out = interpolate(frame, [duration - 12, duration], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const words = text.split(" ");
  return (
    <div style={{ position: "absolute", top: 152, left: 76, right: 76, opacity: out }}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: "2px 16px", justifyContent: "center" }}>
        {words.map((w, i) => {
          const s = spring({ frame: frame - 6 - i * 3, fps, config: { damping: 200, mass: 0.6 } });
          const clean = w.replace(/[^a-zA-Z]/g, "");
          const isAccent = accentWord && clean === accentWord;
          return (
            <span
              key={i}
              style={{
                fontFamily: FONT,
                fontSize: 66,
                fontWeight: 800,
                letterSpacing: -1.4,
                lineHeight: 1.05,
                textAlign: "center",
                color: isAccent ? GOLD : TEXT,
                transform: `translateY(${interpolate(s, [0, 1], [30, 0])}px)`,
                opacity: s,
              }}
            >
              {w}
            </span>
          );
        })}
      </div>
      {sub ? (
        <div
          style={{
            marginTop: 22,
            textAlign: "center",
            fontFamily: FONT,
            fontSize: 31,
            fontWeight: 500,
            color: MUTED,
            lineHeight: 1.3,
            opacity: interpolate(frame, [18, 32], [0, 1], { extrapolateRight: "clamp" }),
          }}
        >
          {sub}
        </div>
      ) : null}
    </div>
  );
};

// ----------------------------------------------------------------------------- Scenes
const ShotScene: React.FC<{
  src: string;
  headline: string;
  sub?: string;
  accentWord?: string;
  duration: number;
  zoomFrom: number;
  zoomTo: number;
  focusFrom: number;
  focusTo: number;
  glow?: number;
}> = (p) => (
  <AbsoluteFill>
    <Headline text={p.headline} sub={p.sub} accentWord={p.accentWord} duration={p.duration} />
    <PhoneShot
      src={p.src}
      duration={p.duration}
      zoomFrom={p.zoomFrom}
      zoomTo={p.zoomTo}
      focusFrom={p.focusFrom}
      focusTo={p.focusTo}
      glow={p.glow}
    />
  </AbsoluteFill>
);

const Intro: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const out = interpolate(frame, [duration - 16, duration], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity: out }}>
      <Columns progress={spring({ frame: frame - 4, fps, config: { damping: 200 } })} />
      <div style={{ display: "flex", marginTop: 36 }}>
        {"MARBLE".split("").map((c, i) => {
          const s = spring({ frame: frame - 10 - i * 4, fps, config: { damping: 200, mass: 0.6 } });
          return (
            <span
              key={i}
              style={{
                fontFamily: FONT,
                fontSize: 112,
                fontWeight: 800,
                letterSpacing: 8,
                color: TEXT,
                transform: `translateY(${interpolate(s, [0, 1], [44, 0])}px)`,
                opacity: s,
              }}
            >
              {c}
            </span>
          );
        })}
      </div>
      <div
        style={{
          marginTop: 20,
          fontFamily: FONT,
          fontSize: 35,
          letterSpacing: 1,
          color: MUTED,
          opacity: interpolate(frame, [34, 52], [0, 1], { extrapolateRight: "clamp" }),
        }}
      >
        Your training, set in stone.
      </div>
    </AbsoluteFill>
  );
};

const CTA: React.FC<{ duration: number }> = ({ duration }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const inO = interpolate(frame, [0, 16], [0, 1], { extrapolateRight: "clamp" });
  const title = spring({ frame: frame - 4, fps, config: { damping: 200 } });
  const btn = spring({ frame: frame - 24, fps, config: { damping: 180, mass: 0.7 } });
  const pulse = 1 + Math.sin(frame / 12) * 0.02;
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity: inO }}>
      <Columns progress={spring({ frame: frame - 2, fps, config: { damping: 200 } })} />
      <div
        style={{
          marginTop: 30,
          fontFamily: FONT,
          fontSize: 104,
          fontWeight: 800,
          letterSpacing: 6,
          color: TEXT,
          transform: `translateY(${interpolate(title, [0, 1], [30, 0])}px)`,
        }}
      >
        MARBLE
      </div>
      <div style={{ marginTop: 12, fontFamily: FONT, fontSize: 37, color: MUTED }}>
        Build something that lasts.
      </div>
      <div style={{ marginTop: 56, transform: `scale(${interpolate(btn, [0, 1], [0.8, 1]) * pulse})`, opacity: btn }}>
        <div
          style={{
            padding: "26px 56px",
            borderRadius: 50,
            background: `linear-gradient(180deg, ${GOLD}, #c2902f)`,
            color: "#1a1206",
            fontFamily: FONT,
            fontSize: 38,
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

// ----------------------------------------------------------------------------- Progress bar
const ProgressBar: React.FC = () => {
  const f = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const w = interpolate(f, [0, durationInFrames], [0, 1080], { extrapolateRight: "clamp" });
  return (
    <div
      style={{
        position: "absolute",
        bottom: 0,
        left: 0,
        height: 6,
        width: w,
        background: `linear-gradient(90deg, rgba(232,178,74,0.35), ${GOLD})`,
      }}
    />
  );
};

// ----------------------------------------------------------------------------- Composition
export const MarbleAd: React.FC = () => {
  return (
    <AbsoluteFill style={{ fontFamily: FONT, backgroundColor: "#07070A" }}>
      <Background />

      <Sequence from={0} durationInFrames={120}>
        <Intro duration={120} />
      </Sequence>

      <Sequence from={120} durationInFrames={150}>
        <ShotScene
          src="shots/quicklog.png"
          headline="Log every set in seconds."
          sub="Weight, reps, rest — captured in a tap."
          duration={150}
          zoomFrom={1.08}
          zoomTo={1.0}
          focusFrom={0.34}
          focusTo={0.46}
        />
      </Sequence>

      <Sequence from={270} durationInFrames={150}>
        <ShotScene
          src="shots/calendar.png"
          headline="Show up. Build the habit."
          sub="Your whole training history, at a glance."
          duration={150}
          zoomFrom={1.0}
          zoomTo={1.07}
          focusFrom={0.3}
          focusTo={0.34}
        />
      </Sequence>

      <Sequence from={420} durationInFrames={150}>
        <ShotScene
          src="shots/trends.png"
          headline="Watch your strength compound."
          sub="Volume, PRs and consistency, visualised."
          duration={150}
          zoomFrom={1.08}
          zoomTo={1.0}
          focusFrom={0.42}
          focusTo={0.52}
        />
      </Sequence>

      <Sequence from={570} durationInFrames={180}>
        <ShotScene
          src="shots/empire.png"
          headline="Every rep becomes Talents."
          sub="Spend them building a marble civilization."
          accentWord="Talents"
          duration={180}
          zoomFrom={1.3}
          zoomTo={1.06}
          focusFrom={0.12}
          focusTo={0.56}
          glow={72}
        />
      </Sequence>

      <Sequence from={750} durationInFrames={180}>
        <ShotScene
          src="shots/tribute.png"
          headline="A reward every day you train."
          sub="Rest days never break your streak."
          accentWord="reward"
          duration={180}
          zoomFrom={1.16}
          zoomTo={1.03}
          focusFrom={0.1}
          focusTo={0.24}
          glow={60}
        />
      </Sequence>

      <Sequence from={930} durationInFrames={120}>
        <CTA duration={120} />
      </Sequence>

      <ProgressBar />
    </AbsoluteFill>
  );
};
