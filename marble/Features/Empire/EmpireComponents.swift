import SwiftUI

// MARK: - Motion gating

/// Drives continuous decorative motion. Hands its content an ever-advancing time value, but
/// collapses to a single fixed frame (`t == 0`) when motion should be reduced — Reduce Motion,
/// snapshot tests, or UI tests (see `TestHooks.reduceDecorativeMotion`). This keeps the Empire
/// scene lively for real users while staying deterministic for snapshots and respectful of
/// accessibility / battery. Particle layouts seed off per-element offsets, so the frozen `t == 0`
/// frame is still a well-distributed still life rather than everything stacked at the origin.
struct AnimatedPhase<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let content: (TimeInterval) -> Content

    init(@ViewBuilder content: @escaping (TimeInterval) -> Content) {
        self.content = content
    }

    var body: some View {
        if reduceMotion || TestHooks.reduceDecorativeMotion {
            content(0)
        } else {
            TimelineView(.animation) { timeline in
                content(timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }
}

// MARK: - Deterministic pseudo-randomness

/// Fractional part — the building block of the classic GPU hash below.
private func empireFrac(_ x: Double) -> Double { x - floor(x) }

/// Stable per-index pseudo-randoms in 0...1 (the well-worn `sin · large constant` shader hash).
/// Deterministic so the frozen scene frame is identical every render.
private func empireHash(_ i: Int, _ salt: Double) -> Double {
    empireFrac(sin((Double(i) + 1) * salt) * 43758.5453)
}

// MARK: - Gradient glyph (the lit, dimensional monument symbol)

/// A single SF Symbol rendered as a lit, gradient-filled marble form: a palette gradient body, a
/// white top sheen for a 3D edge, and a coloured glow. Shared by the row/goal medallions, the
/// skyline silhouettes, and the Tribute/Relic visuals so the dimensional treatment is defined once.
struct GradientGlyph: View {
    let symbolName: String
    let palette: EmpirePalette
    let pointSize: CGFloat
    var weight: Font.Weight = .regular
    var grayscale: Bool = false
    var glowOpacity: Double = 0
    var dropShadow: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: pointSize, weight: weight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(bodyStyle)
            .overlay {
                if !grayscale {
                    // Top-down white sheen → reads as a lit upper edge (fake 3D).
                    Image(systemName: symbolName)
                        .font(.system(size: pointSize, weight: weight))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            }
            .shadow(color: palette.glow.opacity(glowOpacity), radius: glowOpacity > 0 ? pointSize * 0.3 : 0)
            // A subtle dark shadow grounds light-sky silhouettes; the coloured glow pops on dark skies.
            .shadow(color: .black.opacity(dropShadow ? 0.28 : 0), radius: dropShadow ? 4 : 0, y: dropShadow ? 3 : 0)
    }

    private var bodyStyle: AnyShapeStyle {
        grayscale
            ? AnyShapeStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.55))
            : AnyShapeStyle(palette.emblemGradient)
    }
}

// MARK: - Monument emblem (replaces the flat row/goal icon)

enum MonumentEmblemState {
    case locked       // age not yet unlocked
    case idle         // unlocked, not yet affordable, not built
    case affordable   // unlocked and you can afford it now
    case built        // raised
}

/// A monument on a tinted marble medallion: glowing plinth + dimensional `GradientGlyph`. The flat
/// gray `Image` it replaces carried no state; this signals locked / idle / affordable / built
/// through colour and glow, and (when `animated`) breathes for the focal monuments.
struct MonumentEmblem: View {
    let structure: EmpireStructure
    let state: MonumentEmblemState
    var size: CGFloat = 44
    var animated: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var palette: EmpirePalette { structure.age.palette }

    var body: some View {
        if animated && state != .locked {
            AnimatedPhase { t in plinth(glow: breathingGlow(t)) }
        } else {
            plinth(glow: restingGlow)
        }
    }

    private func breathingGlow(_ t: TimeInterval) -> Double {
        let base = state == .built ? 0.5 : 0.3
        return base + 0.28 * (0.5 + 0.5 * sin(t * 1.4))
    }

    private var restingGlow: Double {
        switch state {
        case .built: return 0.48
        case .affordable: return 0.4
        case .idle: return 0.26
        case .locked: return 0
        }
    }

    private func plinth(glow: Double) -> some View {
        let corner = size * 0.28
        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(plinthFill)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(plinthStroke, lineWidth: 0.75)
                )

            if state != .locked {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [palette.glow.opacity(glow * 0.55), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.62
                        )
                    )
            }

            GradientGlyph(
                symbolName: structure.resolvedSymbolName,
                palette: palette,
                pointSize: size * 0.52,
                grayscale: state == .locked,
                glowOpacity: state == .locked ? 0 : glow
            )
            .opacity(state == .locked ? 0.45 : 1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var plinthFill: Color {
        state == .locked
            ? Theme.controlFillColor(for: colorScheme)
            : palette.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
    }

    private var plinthStroke: Color {
        state == .locked
            ? Theme.subtleDividerColor(for: colorScheme)
            : palette.accent.opacity(0.35)
    }
}

extension MonumentEmblem {
    /// Next-goal convenience: the goal is always unlocked and unbuilt, so it reads as `affordable`
    /// once the balance covers its cost, otherwise `idle`.
    init(goal: EmpireStructure, balance: Double, animated: Bool, size: CGFloat) {
        self.init(
            structure: goal,
            state: balance >= goal.cost ? .affordable : .idle,
            size: size,
            animated: animated
        )
    }
}

// MARK: - Talent balance hero

/// The balance number, kept legible (digits run from the theme text colour into the current age's
/// accent, so contrast holds in both schemes) with a slow accent shimmer sweep and a glowing
/// currency mark. Colour tracks the age you're shaping, so the hero advances with you.
struct TalentBalanceHero: View {
    let balance: Double
    let palette: EmpirePalette
    let currencySymbol: String

    @Environment(\.colorScheme) private var colorScheme

    private var text: String { Formatters.compactNumberText(balance) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xs) {
            Image(systemName: currencySymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.emblemGradient)
                .shadow(color: palette.glow.opacity(0.6), radius: 6)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(numberGradient)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
                .overlay { shimmer }
                .mask {
                    Text(text)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }

            Text("Talents")
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text) Talents available")
        .accessibilityIdentifier("Empire.Balance")
    }

    /// Digits run primary-text → accent, so the bulk of each glyph keeps full contrast while the
    /// foot of the number picks up colour.
    private var numberGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.primaryTextColor(for: colorScheme), palette.accent],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var shimmer: some View {
        GeometryReader { geo in
            AnimatedPhase { t in
                let sweep = empireFrac(t * 0.12)
                let x = (sweep * 1.6 - 0.3) * geo.size.width
                LinearGradient(
                    colors: [.clear, palette.glow.opacity(0.85), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.35)
                .offset(x: x)
                .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Goal progress bar

/// Goal-gradient progress toward the next monument: an age-coloured fill on a neutral track, with a
/// travelling shimmer once you can afford it — a small "go build it" pull.
struct GoalProgressBar: View {
    let progress: Double
    let palette: EmpirePalette
    let ready: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            let fillWidth = max(clamped * geo.size.width, ready ? geo.size.width : 6)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.controlFillColor(for: colorScheme))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [palette.emblemLight, palette.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)
                    .shadow(color: palette.glow.opacity(ready ? 0.6 : 0.25), radius: ready ? 6 : 3)
                    .overlay {
                        if ready {
                            AnimatedPhase { t in
                                let x = (empireFrac(t * 0.5) * 1.4 - 0.2) * fillWidth
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.7), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: fillWidth * 0.3)
                                .offset(x: x)
                                .blendMode(.screen)
                            }
                            .clipShape(Capsule())
                            .allowsHitTesting(false)
                        }
                    }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Living skyline (the centerpiece scene)

/// The civilization panorama, reborn as a living scene: a per-age coloured sky, a drifting
/// celestial orb, age-tinted particles, and the built monuments as glowing silhouettes that bob on
/// a marble ground. Decorative — summarized for VoiceOver. Replaces the old flat row of gray glyphs.
struct LivingSkylineView: View {
    let structures: [EmpireStructure]
    let age: EmpireAge
    var relics: [EmpireRelic] = []

    @Environment(\.colorScheme) private var colorScheme

    private let height: CGFloat = 200
    private let baseGlyph: CGFloat = 64
    private var palette: EmpirePalette { age.palette }

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.skyGradient

            // A darker band at the ground line so monuments read on light skies too.
            LinearGradient(
                colors: [.clear, .black.opacity(0.28)],
                startPoint: .center,
                endPoint: .bottom
            )

            AnimatedPhase { t in
                ZStack {
                    celestialOrb(t)
                    ParticleField(style: palette.particleStyle, color: palette.particle, time: t)
                }
            }

            if structures.isEmpty {
                emptyScene
            } else {
                buildings
            }

            // Marble ground line + faint reflection.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.white.opacity(0.55))
                    .frame(height: 1.5)
                LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
            }
            .padding(.bottom, MarbleSpacing.m)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                .stroke(Theme.subtleDividerColor(for: colorScheme), lineWidth: 0.75)
        )
        .overlay(alignment: .topLeading) { ageChip }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("Empire.Skyline")
    }

    private var ageChip: some View {
        HStack(spacing: MarbleSpacing.xxs) {
            Circle()
                .fill(palette.accent)
                .frame(width: 7, height: 7)
                .shadow(color: palette.glow.opacity(0.8), radius: 4)
            Text(age.title)
                .font(MarbleTypography.smallLabel)
                .textCase(.uppercase)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, MarbleSpacing.s)
        .padding(.vertical, MarbleSpacing.xxs)
        .background(Capsule().fill(.black.opacity(0.3)))
        .padding(MarbleSpacing.s)
    }

    private func celestialOrb(_ t: TimeInterval) -> some View {
        let drift = CGFloat(sin(t * 0.05)) * 26
        return Circle()
            .fill(
                RadialGradient(
                    colors: [palette.glow.opacity(0.9), palette.glow.opacity(0.25), .clear],
                    center: .center,
                    startRadius: 2,
                    endRadius: height * 0.42
                )
            )
            .frame(width: height * 0.7, height: height * 0.7)
            .offset(x: drift + height * 0.55, y: -height * 0.22 + CGFloat(cos(t * 0.05)) * 8)
            .blur(radius: 2)
    }

    private var buildings: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            AnimatedPhase { t in
                HStack(alignment: .bottom, spacing: MarbleSpacing.s) {
                    ForEach(Array(structures.enumerated()), id: \.element.id) { index, structure in
                        let bob = CGFloat(sin(t * 0.8 + Double(index) * 1.3)) * 3
                        GradientGlyph(
                            symbolName: structure.resolvedSymbolName,
                            palette: structure.age.palette,
                            pointSize: max(26, baseGlyph * structure.scale),
                            glowOpacity: 0.45,
                            dropShadow: true
                        )
                        .offset(y: bob)
                    }
                    // Collected relics sit among the monuments as small glowing treasures.
                    ForEach(Array(relics.enumerated()), id: \.element.id) { offset, relic in
                        let index = structures.count + offset
                        let bob = CGFloat(sin(t * 0.9 + Double(index) * 1.3)) * 3
                        GradientGlyph(
                            symbolName: relic.resolvedSymbolName,
                            palette: relic.age.palette,
                            pointSize: baseGlyph * 0.4,
                            glowOpacity: 0.5,
                            dropShadow: true
                        )
                        .offset(y: bob)
                    }
                }
                .padding(.horizontal, MarbleSpacing.l)
                .padding(.bottom, MarbleSpacing.m + 6)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minWidth: 0)
            }
        }
        .scrollDisabled(structures.count + relics.count <= 5)
    }

    private var emptyScene: some View {
        // Fixed-height and text-free, so it can never clip. The welcome copy lives below the card.
        Image(systemName: "mountain.2.fill")
            .font(.system(size: 46, weight: .regular))
            .foregroundStyle(
                LinearGradient(
                    colors: [palette.emblemDark.opacity(0.7), palette.emblemDark.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
            .padding(.bottom, MarbleSpacing.l + 4)
    }

    private var accessibilitySummary: String {
        if structures.isEmpty {
            return "Your marble civilization is waiting to be built."
        }
        let names = structures.map(\.name).joined(separator: ", ")
        return "\(age.title). Your skyline: \(names)."
    }
}

/// A field of drifting, twinkling particles tinted to the current age. Pure `Canvas` so even a
/// few dozen points stay cheap. All motion derives from `time`, with deterministic per-particle
/// seeds, so the frozen frame (`time == 0`) is a clean still scene.
private struct ParticleField: View {
    let style: EmpireParticleStyle
    let color: Color
    let time: TimeInterval

    private let count = 34

    var body: some View {
        Canvas { context, size in
            for i in 0..<count {
                let p = particle(i, in: size)
                guard p.opacity > 0.02 else { continue }
                context.opacity = p.opacity
                let rect = CGRect(x: p.x - p.radius, y: p.y - p.radius, width: p.radius * 2, height: p.radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
    }

    private func particle(_ i: Int, in size: CGSize) -> (x: CGFloat, y: CGFloat, radius: CGFloat, opacity: Double) {
        let a = empireHash(i, 12.9898)
        let b = empireHash(i, 78.233)
        let c = empireHash(i, 39.425)
        switch style {
        case .embers:
            let speed = 6 + a * 14
            let cycle = Double(size.height) + 24
            let rise = empireFrac((time * speed) / cycle + c) * cycle
            let x = b * Double(size.width) + sin(time * 0.6 + a * 6.283) * (6 + c * 8)
            let y = Double(size.height) - rise
            let twinkle = 0.4 + 0.6 * abs(sin(time * 1.3 + b * 6.283))
            return (CGFloat(x), CGFloat(y), CGFloat(1.2 + a * 2.0), twinkle * (0.45 + 0.45 * c))
        case .motes:
            let x = b * Double(size.width) + sin(time * 0.35 + a * 6.283) * 10
            let y = c * Double(size.height) * 0.85 + cos(time * 0.3 + b * 6.283) * 8
            let opacity = 0.28 + 0.4 * abs(sin(time * 0.8 + c * 6.283))
            return (CGFloat(x), CGFloat(y), CGFloat(1.0 + a * 1.8), opacity)
        case .sparks:
            let x = b * Double(size.width)
            let y = c * Double(size.height) * 0.8
            let twinkle = pow(abs(sin(time * 1.6 + a * 6.283)), 3)
            return (CGFloat(x), CGFloat(y), CGFloat(0.8 + a * 1.6), 0.2 + 0.8 * twinkle)
        }
    }
}

// MARK: - Build celebration

/// A single build payoff. Recreated per event (keyed by `id`) so the overlay's clock restarts.
struct EmpireCelebrationEvent: Identifiable, Equatable {
    let id = UUID()
    let age: EmpireAge
    let title: String
}

/// The reward moment when a monument is raised: a radial spark burst in the age's palette plus a
/// rising "name raised!" banner. Purely a tap-triggered overlay — `allowsHitTesting(false)` so it
/// never blocks the Build button, and skipped entirely under reduced motion (the success haptic and
/// animated balance drop still land). Never appears in snapshots (no tap occurs there).
struct EmpireCelebrationOverlay: View {
    let event: EmpireCelebrationEvent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private let duration: Double = 1.25
    private var palette: EmpirePalette { event.age.palette }

    var body: some View {
        if reduceMotion || TestHooks.reduceDecorativeMotion {
            EmptyView()
        } else {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                let p = min(max(elapsed / duration, 0), 1)
                ZStack {
                    sparkBurst(progress: p)
                    banner(progress: p)
                }
                .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
        }
    }

    private func sparkBurst(progress p: Double) -> some View {
        let eased = 1 - pow(1 - p, 3) // easeOut
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
            let maxDistance = min(size.width, size.height) * 0.42
            let sparkCount = 30
            for i in 0..<sparkCount {
                let angle = (Double(i) / Double(sparkCount)) * 2 * .pi + empireHash(i, 12.9898) * 0.4
                let reach = maxDistance * (0.55 + empireHash(i, 78.233) * 0.45)
                let distance = reach * eased
                let x = center.x + CGFloat(cos(angle)) * CGFloat(distance)
                let y = center.y + CGFloat(sin(angle)) * CGFloat(distance) + CGFloat(eased * eased * 22) // slight gravity
                let radius = CGFloat(2 + empireHash(i, 39.425) * 2.5) * CGFloat(1 - p * 0.5)
                context.opacity = max(0, 1 - p)
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                let tint = i.isMultiple(of: 3) ? palette.glow : palette.accent
                context.fill(Path(ellipseIn: rect), with: .color(tint))
            }
        }
        .blendMode(.plusLighter)
    }

    private func banner(progress p: Double) -> some View {
        let appear = min(p / 0.2, 1)
        let appearEased = 1 - pow(1 - appear, 3)
        let fade = p > 0.7 ? max(0, (1 - p) / 0.3) : 1
        return HStack(spacing: MarbleSpacing.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(palette.emblemGradient)
            Text("\(event.title) raised!")
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, MarbleSpacing.m)
        .padding(.vertical, MarbleSpacing.s)
        .background(
            Capsule()
                .fill(.black.opacity(0.55))
                .overlay(Capsule().stroke(palette.accent.opacity(0.7), lineWidth: 1))
                .shadow(color: palette.glow.opacity(0.6), radius: 12)
        )
        .scaleEffect(0.85 + 0.15 * appearEased)
        .opacity(appearEased * fade)
        .offset(y: -60 - 16 * appearEased)
    }
}
