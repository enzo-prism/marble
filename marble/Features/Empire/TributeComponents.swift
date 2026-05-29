import SwiftUI

// MARK: - Relic emblem

/// A collectible relic on a tinted marble medallion. Collected relics show in full colour; locked
/// ones are a dim silhouette with a "?" so the gallery reads as "collect them all" without revealing
/// (or obfuscating) anything. Reuses the shared `GradientGlyph` treatment.
struct RelicEmblem: View {
    let relic: EmpireRelic
    var size: CGFloat = 44
    var collected: Bool = true
    var animated: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var palette: EmpirePalette { relic.age.palette }

    var body: some View {
        if collected && animated {
            AnimatedPhase { t in medallion(glow: 0.4 + 0.28 * (0.5 + 0.5 * sin(t * 1.4))) }
        } else {
            medallion(glow: collected ? 0.42 : 0)
        }
    }

    private func medallion(glow: Double) -> some View {
        let corner = size * 0.28
        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(collected ? palette.accent.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                 : Theme.controlFillColor(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(collected ? palette.accent.opacity(0.35) : Theme.subtleDividerColor(for: colorScheme),
                                lineWidth: 0.75)
                )

            if collected {
                Circle()
                    .fill(RadialGradient(colors: [palette.glow.opacity(glow * 0.55), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.62))
                GradientGlyph(symbolName: relic.resolvedSymbolName, palette: palette,
                              pointSize: size * 0.5, glowOpacity: glow)
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme).opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Tribute card (the daily hook, pinned to the top of Empire)

struct TributeCard: View {
    enum Phase {
        case earn      // hasn't trained today
        case ready     // trained, unclaimed
        case claimed   // already claimed today
    }

    let phase: Phase
    let streak: Int
    let freezes: Int
    let nextMilestone: (threshold: Int, daysAway: Int)?
    let palette: EmpirePalette
    let onClaim: () -> Void
    let onLogSet: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(spacing: MarbleSpacing.s) {
                emblem
                VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                    Text("DAILY TRIBUTE")
                        .font(MarbleTypography.smallLabel)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.accent)
                    Text(title)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    Text(subtitle)
                        .font(MarbleTypography.rowMeta)
                        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: MarbleSpacing.s)
            }

            statusRow

            switch phase {
            case .earn:
                Button(action: onLogSet) {
                    Label("Log a Set", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
                .accessibilityIdentifier("Empire.Tribute.LogSet")
            case .ready:
                Button(action: onClaim) {
                    Label("Claim Tribute", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
                .accessibilityIdentifier("Empire.Tribute.Claim")
            case .claimed:
                EmptyView()
            }
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Empire.Tribute")
    }

    @ViewBuilder
    private var emblem: some View {
        let corner = MarbleLayout.rowIconSize * 0.5
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(palette.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(palette.accent.opacity(0.35), lineWidth: 0.75))
            if phase == .ready {
                AnimatedPhase { t in glyph(glow: 0.4 + 0.3 * (0.5 + 0.5 * sin(t * 1.6))) }
            } else {
                glyph(glow: phase == .claimed ? 0.4 : 0.22)
            }
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }

    private func glyph(glow: Double) -> some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [palette.glow.opacity(glow * 0.55), .clear],
                                         center: .center, startRadius: 0, endRadius: 30))
            GradientGlyph(symbolName: phase == .claimed ? "checkmark.seal.fill" : "cube.fill",
                          palette: palette, pointSize: 26, glowOpacity: glow)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if phase != .earn || streak > 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MarbleSpacing.xs) { chips }
                VStack(alignment: .leading, spacing: MarbleSpacing.xs) { chips }
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        chip(text: "\(streak)-day streak", systemImage: "flame.fill")
        if freezes > 0 {
            chip(text: "\(freezes) reprieve\(freezes == 1 ? "" : "s")", systemImage: "snowflake")
        }
        if let next = nextMilestone {
            chip(text: "Guild honour in \(next.daysAway)", systemImage: "rosette")
        }
    }

    private func chip(text: String, systemImage: String) -> some View {
        HStack(spacing: MarbleSpacing.xxxs) {
            Image(systemName: systemImage).foregroundStyle(palette.accent).accessibilityHidden(true)
            Text(text).lineLimit(1).foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        }
        .fixedSize()
        .font(MarbleTypography.smallLabel)
        .padding(.horizontal, MarbleSpacing.s)
        .padding(.vertical, MarbleSpacing.xxs)
        .background(Capsule().fill(Theme.chipFillColor(for: colorScheme)))
        .overlay(Capsule().stroke(palette.accent.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch phase {
        case .earn: return "Today's Tribute awaits"
        case .ready: return "Your Tribute is ready"
        case .claimed: return "Tribute claimed"
        }
    }

    private var subtitle: String {
        switch phase {
        case .earn: return "Log a set to quarry today's reward."
        case .ready: return "You trained today — quarry your reward."
        case .claimed: return "Rest or train — your reward returns tomorrow."
        }
    }
}

// MARK: - Tribute reveal (the "quarry dig" payoff)

/// The reward reveal shown after claiming: a palette spark burst behind a card naming the tier,
/// bonus Talents, any relic, and the streak. Tap-triggered only (never in snapshots); the burst is
/// gated so Reduce-Motion / tests render the result instantly.
struct TributeRevealView: View {
    let outcome: EmpireTributeOutcome
    let palette: EmpirePalette
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private var animate: Bool { !reduceMotion && !TestHooks.reduceDecorativeMotion }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            if animate {
                TimelineView(.animation) { timeline in
                    burst(progress: min(max(timeline.date.timeIntervalSince(start) / 0.9, 0), 1))
                }
            }

            card
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("Empire.Tribute.Reveal")
    }

    private func burst(progress p: Double) -> some View {
        let eased = 1 - pow(1 - p, 3)
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
            let maxDistance = min(size.width, size.height) * 0.4
            for i in 0..<34 {
                var rng = EmpireSeededRNG(seed: UInt64(i + 1) &* 0x9E37)
                let angle = (Double(i) / 34) * 2 * .pi + rng.unit() * 0.3
                let reach = maxDistance * (0.5 + rng.unit() * 0.5)
                let x = center.x + CGFloat(cos(angle)) * CGFloat(reach * eased)
                let y = center.y + CGFloat(sin(angle)) * CGFloat(reach * eased) + CGFloat(eased * eased * 20)
                let radius = CGFloat(2 + rng.unit() * 2.5) * CGFloat(1 - p * 0.5)
                context.opacity = max(0, 1 - p)
                let tint = i.isMultiple(of: 3) ? palette.glow : palette.accent
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(tint))
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private var card: some View {
        VStack(spacing: MarbleSpacing.s) {
            Text(outcome.tier.title.uppercased())
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(palette.accent)
            Text(outcome.tier.headline)
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                .multilineTextAlignment(.center)

            HStack(spacing: MarbleSpacing.xxs) {
                Image(systemName: "laurel.leading").foregroundStyle(palette.emblemGradient)
                Text("+\(Formatters.compactNumberText(outcome.totalBonus)) Talents")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .monospacedDigit()
                Image(systemName: "laurel.trailing").foregroundStyle(palette.emblemGradient)
            }
            .padding(.top, MarbleSpacing.xxs)

            if !outcome.relics.isEmpty {
                VStack(spacing: MarbleSpacing.xs) {
                    ForEach(outcome.relics) { relic in
                        HStack(spacing: MarbleSpacing.s) {
                            RelicEmblem(relic: relic, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(relic.name)
                                    .font(MarbleTypography.rowTitle)
                                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                                Text("\(relic.rarity.label) relic — added to your city")
                                    .font(MarbleTypography.rowMeta)
                                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(MarbleSpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: MarbleCornerRadius.medium, style: .continuous)
                            .fill(Theme.chipFillColor(for: colorScheme)))
                    }
                }
            }

            Text(streakNote)
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .multilineTextAlignment(.center)

            Button(action: onDismiss) {
                Text("Collect").frame(maxWidth: .infinity)
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
            .accessibilityIdentifier("Empire.Tribute.Collect")
            .padding(.top, MarbleSpacing.xxs)
        }
        .padding(MarbleSpacing.l)
        .frame(maxWidth: 320)
        .background(RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
            .fill(Theme.surfaceColor(for: colorScheme)))
        .overlay(RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
            .stroke(palette.accent.opacity(0.5), lineWidth: 1))
        .shadow(color: palette.glow.opacity(0.5), radius: 24)
        .padding(MarbleSpacing.xl)
    }

    private var streakNote: String {
        var note = "\(outcome.newStreak)-day streak"
        if !outcome.milestonesClaimed.isEmpty {
            note += " · Guild honour unlocked!"
        } else if outcome.freezesConsumed > 0 {
            note += " · a reprieve kept it alive"
        }
        return note
    }

    private var accessibilityLabel: String {
        var parts = ["\(outcome.tier.title). Plus \(Formatters.compactNumberText(outcome.totalBonus)) Talents."]
        for relic in outcome.relics { parts.append("\(relic.name) relic collected.") }
        parts.append("\(outcome.newStreak) day streak.")
        return parts.joined(separator: " ")
    }
}

// MARK: - Relic gallery

/// The collection meta-goal: the full relic set, collected in colour, uncollected as silhouettes.
struct RelicGalleryView: View {
    let collectedIDs: Set<String>

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: MarbleSpacing.s)]

    var body: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Relics")
                    .font(MarbleTypography.sectionTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                Spacer(minLength: MarbleSpacing.s)
                Text("\(collectedIDs.count)/\(EmpireRelic.totalCount)")
                    .font(MarbleTypography.smallLabel)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            Text("Unearthed from your Daily Tributes. Each one decorates your city.")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, spacing: MarbleSpacing.m) {
                ForEach(EmpireRelic.catalog) { relic in
                    let owned = collectedIDs.contains(relic.id)
                    VStack(spacing: MarbleSpacing.xxs) {
                        RelicEmblem(relic: relic, size: 56, collected: owned)
                        Text(owned ? relic.name : "Locked")
                            .font(MarbleTypography.smallLabel)
                            .foregroundStyle(owned ? Theme.secondaryTextColor(for: colorScheme)
                                                   : Theme.secondaryTextColor(for: colorScheme).opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(owned ? "\(relic.name), \(relic.rarity.label) relic, collected"
                                              : "Undiscovered relic")
                }
            }
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
        .accessibilityIdentifier("Empire.Relics")
    }
}
