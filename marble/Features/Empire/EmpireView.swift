import SwiftUI
import SwiftData

struct EmpireView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var quickLog: QuickLogCoordinator

    @Query private var states: [EmpireState]

    @Query(sort: \SetEntry.performedAt, order: .reverse)
    private var entries: [SetEntry]

    private let calendar = Calendar.current
    private let currencySymbol = "laurel.leading"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarbleSpacing.l) {
                    balanceCard

                    MarbleSkylineView(structures: builtStructures, ageTitle: currentAge.title)

                    if builtCount == 0 && balance == 0 {
                        emptyPrompt
                    }

                    nextGoalCard

                    ForEach(EmpireAge.allCases) { age in
                        ageSection(age)
                    }
                }
                .padding(.horizontal, MarbleLayout.pagePadding)
                .padding(.top, MarbleSpacing.xs)
                .padding(.bottom, MarbleSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.backgroundColor(for: colorScheme))
            .accessibilityIdentifier("Empire.Scroll")
            .navigationTitle("Empire")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarGlassBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddSetToolbarButton()
                }
            }
            .onAppear(perform: refreshLifetime)
            .onChange(of: entries.count) { _, _ in
                refreshLifetime()
            }
        }
    }

    // MARK: Balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: MarbleSpacing.xs) {
                Image(systemName: resolvedCurrencySymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)
                Text(talentText(balance))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("Talents")
                    .font(MarbleTypography.rowSubtitle)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(talentText(balance)) Talents available")
            .accessibilityIdentifier("Empire.Balance")

            Text("Earned from \(talentText(effectiveLifetime)) lb of lifetime volume.")
                .font(MarbleTypography.rowMeta)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: MarbleSpacing.xs) {
                    statChips
                }
                VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                    statChips
                }
            }
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground()
    }

    @ViewBuilder
    private var statChips: some View {
        chip(text: streakLabel, systemImage: "flame.fill")
        chip(text: "Today +\(talentText(earnedToday))", systemImage: resolvedCurrencySymbol)
        chip(text: "\(builtCount)/\(EmpireEconomy.totalStructureCount) built", systemImage: "building.columns")
    }

    private func chip(text: String, systemImage: String) -> some View {
        HStack(spacing: MarbleSpacing.xxxs) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
        }
        // Intrinsic width so the chips never get squeezed/clipped inside the HStack;
        // `ViewThatFits` falls back to the vertical stack when they no longer fit.
        .fixedSize()
        .font(MarbleTypography.smallLabel)
        .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
        .padding(.horizontal, MarbleSpacing.s)
        .padding(.vertical, MarbleSpacing.xxs)
        .background(Capsule().fill(Theme.chipFillColor(for: colorScheme)))
        .overlay(Capsule().stroke(Theme.dividerColor(for: colorScheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var emptyPrompt: some View {
        VStack(alignment: .leading, spacing: MarbleSpacing.s) {
            Text("Your civilization awaits")
                .font(MarbleTypography.rowTitle)
                .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            Text("Every pound you move becomes a Talent. Log a set to lay your first stone.")
                .font(MarbleTypography.rowSubtitle)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                quickLog.open()
            } label: {
                Label("Log a Set", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
            .accessibilityIdentifier("Empire.LogSet")
        }
        .padding(MarbleSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
    }

    // MARK: Next goal

    @ViewBuilder
    private var nextGoalCard: some View {
        if let goal = nextGoal {
            VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
                Text("NEXT MONUMENT")
                    .font(MarbleTypography.smallLabel)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .textCase(.uppercase)

                HStack(spacing: MarbleSpacing.s) {
                    structureIcon(goal, size: MarbleLayout.rowIconSize)
                    VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                        Text(goal.name)
                            .font(MarbleTypography.rowTitle)
                            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                        Text(goal.flavor)
                            .font(MarbleTypography.rowMeta)
                            .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: MarbleSpacing.s)
                }

                ProgressView(value: min(balance / goal.cost, 1.0))
                    .tint(Theme.primaryTextColor(for: colorScheme))
                    .accessibilityHidden(true)

                Text(goalProgressText(goal))
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }
            .padding(MarbleSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Next monument, \(goal.name). \(goalProgressText(goal))")
            .accessibilityIdentifier("Empire.NextGoal")
        } else if builtCount > 0 {
            VStack(alignment: .leading, spacing: MarbleSpacing.xxs) {
                Text("Civilization complete")
                    .font(MarbleTypography.rowTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                Text("Every monument is built. Keep training to grow your legend.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MarbleSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
            .accessibilityIdentifier("Empire.Complete")
        }
    }

    // MARK: Build sections

    private func ageSection(_ age: EmpireAge) -> some View {
        let unlocked = EmpireEconomy.isAgeUnlocked(age, builtIDs: builtIDs)
        let structures = EmpireEconomy.structures(in: age)
        let builtInAge = structures.filter { builtIDs.contains($0.id) }.count

        return VStack(alignment: .leading, spacing: MarbleSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(age.title)
                    .font(MarbleTypography.sectionTitle)
                    .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                Spacer(minLength: MarbleSpacing.s)
                Text(unlocked ? "\(builtInAge)/\(structures.count)" : "Locked")
                    .font(MarbleTypography.smallLabel)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
            }

            if unlocked {
                Text(age.tagline)
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Build the \(previousAgeTitle(age)) to unlock this age.")
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(structures.enumerated()), id: \.element.id) { index, structure in
                    if index > 0 {
                        Divider().background(Theme.subtleDividerColor(for: colorScheme))
                    }
                    structureRow(structure, unlocked: unlocked)
                }
            }
            .marbleCardBackground(cornerRadius: MarbleCornerRadius.medium)
            .opacity(unlocked ? 1 : 0.55)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Empire.Age.\(age.rawValue)")
    }

    private func structureRow(_ structure: EmpireStructure, unlocked: Bool) -> some View {
        let built = builtIDs.contains(structure.id)
        let affordable = balance >= structure.cost

        return HStack(spacing: MarbleSpacing.s) {
            HStack(spacing: MarbleSpacing.s) {
                structureIcon(structure, size: MarbleLayout.rowIconSize)

                VStack(alignment: .leading, spacing: MarbleLayout.rowInnerSpacing) {
                    Text(structure.name)
                        .font(MarbleTypography.rowTitle)
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                    HStack(spacing: MarbleSpacing.xxxs) {
                        Image(systemName: resolvedCurrencySymbol)
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(talentText(structure.cost))
                            .monospacedDigit()
                    }
                    .font(MarbleTypography.rowMeta)
                    .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowAccessibilityLabel(structure, built: built, unlocked: unlocked))

            Spacer(minLength: MarbleSpacing.s)

            trailingControl(structure, built: built, unlocked: unlocked, affordable: affordable)
        }
        .padding(.vertical, MarbleSpacing.s)
        .padding(.horizontal, MarbleSpacing.m)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func trailingControl(_ structure: EmpireStructure, built: Bool, unlocked: Bool, affordable: Bool) -> some View {
        if built {
            Label("Built", systemImage: "checkmark.seal.fill")
                .labelStyle(.titleAndIcon)
                .font(MarbleTypography.smallLabel)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(structure.name) built")
                .accessibilityIdentifier("Empire.Built.\(structure.id)")
        } else if !unlocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .accessibilityHidden(true)
        } else {
            Button("Build") {
                build(structure)
            }
            .buttonStyle(MarbleActionButtonStyle(isEnabledOverride: affordable, prominence: affordable ? .primary : .standard))
            .allowsHitTesting(affordable)
            .accessibilityLabel(affordable ? "Build \(structure.name)" : "Build \(structure.name), need more Talents")
            .accessibilityIdentifier("Empire.Build.\(structure.id)")
        }
    }

    private func structureIcon(_ structure: EmpireStructure, size: CGFloat) -> some View {
        Image(systemName: structure.resolvedSymbolName)
            .font(.system(size: size * 0.7, weight: .regular))
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    // MARK: Derived state

    private var state: EmpireState? { states.first }

    private var computedLifetime: Double {
        EmpireEconomy.lifetimeTalents(from: entries)
    }

    private var effectiveLifetime: Double {
        max(state?.storedLifetimeTalents ?? 0, computedLifetime)
    }

    private var balance: Double {
        max(0, effectiveLifetime - (state?.spentTalents ?? 0))
    }

    private var builtIDs: Set<String> {
        state?.builtStructureIDSet ?? []
    }

    private var builtStructures: [EmpireStructure] {
        EmpireEconomy.builtStructures(ids: builtIDs)
    }

    private var builtCount: Int {
        EmpireEconomy.builtCount(in: builtIDs)
    }

    private var currentAge: EmpireAge {
        EmpireEconomy.currentAge(builtIDs: builtIDs)
    }

    private var nextGoal: EmpireStructure? {
        EmpireEconomy.nextGoal(builtIDs: builtIDs)
    }

    private var earnedToday: Double {
        EmpireEconomy.talentsEarned(on: AppEnvironment.now, from: entries, calendar: calendar)
    }

    private var resolvedCurrencySymbol: String {
        UIImage(systemName: currencySymbol) != nil ? currencySymbol : "centsign.circle.fill"
    }

    private func goalProgressText(_ goal: EmpireStructure) -> String {
        if balance >= goal.cost {
            return "Ready to build — \(talentText(balance)) Talents banked."
        }
        let remaining = goal.cost - balance
        return "\(talentText(balance)) of \(talentText(goal.cost)) · \(talentText(remaining)) to go"
    }

    private func previousAgeTitle(_ age: EmpireAge) -> String {
        EmpireAge(rawValue: age.rawValue - 1)?.title ?? age.title
    }

    private func rowAccessibilityLabel(_ structure: EmpireStructure, built: Bool, unlocked: Bool) -> String {
        if built {
            return "\(structure.name), built"
        }
        if !unlocked {
            return "\(structure.name), locked, costs \(talentText(structure.cost)) Talents"
        }
        return "\(structure.name), costs \(talentText(structure.cost)) Talents"
    }

    private func talentText(_ value: Double) -> String {
        Formatters.compactNumberText(value)
    }

    // MARK: Day streak (consecutive logged days ending today or yesterday)

    private var streakLabel: String {
        let count = currentStreak
        return "Streak \(count) \(count == 1 ? "day" : "days")"
    }

    private var currentStreak: Int {
        let loggedDays = Set(entries.map { calendar.startOfDay(for: $0.performedAt) })
        guard !loggedDays.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: AppEnvironment.now)
        let start: Date?
        if loggedDays.contains(today) {
            start = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  loggedDays.contains(yesterday) {
            start = yesterday
        } else {
            start = nil
        }
        guard let streakStart = start else { return 0 }
        var count = 0
        var cursor = streakStart
        while loggedDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // MARK: Actions

    private func refreshLifetime() {
        let target = ensuredState()
        let computed = computedLifetime
        if computed > target.storedLifetimeTalents {
            target.updateLifetimeTalents(computed)
            target.updatedAt = AppEnvironment.now
            try? modelContext.save()
        }
    }

    private func build(_ structure: EmpireStructure) {
        let target = ensuredState()
        target.updateLifetimeTalents(computedLifetime)
        guard target.purchase(structure) else { return }
        try? modelContext.save()
    }

    private func ensuredState() -> EmpireState {
        if let existing = state {
            return existing
        }
        let now = AppEnvironment.now
        let created = EmpireState(storedLifetimeTalents: computedLifetime, createdAt: now, updatedAt: now)
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }
}

/// The civilization panorama: built monuments rendered as a monochrome marble skyline
/// that grows denser as the user trains. Decorative — summarized for VoiceOver.
private struct MarbleSkylineView: View {
    let structures: [EmpireStructure]
    let ageTitle: String

    @Environment(\.colorScheme) private var colorScheme

    private let height: CGFloat = 188
    private let baseGlyph: CGFloat = 66

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.surfaceColor(for: colorScheme),
                            Theme.controlFillColor(for: colorScheme)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if structures.isEmpty {
                emptyScene
            } else {
                skyline
            }

            Rectangle()
                .fill(Theme.dividerColor(for: colorScheme))
                .frame(height: 1.5)
                .padding(.bottom, MarbleSpacing.m)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MarbleCornerRadius.large, style: .continuous)
                .stroke(Theme.subtleDividerColor(for: colorScheme), lineWidth: 0.75)
        )
        .overlay(alignment: .topLeading) {
            Text(ageTitle)
                .font(MarbleTypography.smallLabel)
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryTextColor(for: colorScheme))
                .padding(.horizontal, MarbleSpacing.s)
                .padding(.vertical, MarbleSpacing.xxs)
                .background(Capsule().fill(Theme.chipFillColor(for: colorScheme)))
                .padding(MarbleSpacing.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("Empire.Skyline")
    }

    private var skyline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: MarbleSpacing.s) {
                ForEach(structures) { structure in
                    Image(systemName: structure.resolvedSymbolName)
                        .font(.system(size: max(24, baseGlyph * structure.scale), weight: .regular))
                        .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
                }
            }
            .padding(.horizontal, MarbleSpacing.l)
            .padding(.bottom, MarbleSpacing.m + 4)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(minWidth: 0)
        }
        .scrollDisabled(structures.count <= 5)
    }

    private var emptyScene: some View {
        // Purely decorative and fixed-height: no Dynamic Type text lives here, so it can
        // never clip. The welcome copy is rendered below the card in the scroll area.
        Image(systemName: "mountain.2.fill")
            .font(.system(size: 46, weight: .regular))
            .foregroundStyle(Theme.subtleDividerColor(for: colorScheme))
            .padding(.bottom, MarbleSpacing.l)
    }

    private var accessibilitySummary: String {
        if structures.isEmpty {
            return "Your marble civilization is waiting to be built."
        }
        let names = structures.map(\.name).joined(separator: ", ")
        return "\(ageTitle). Your skyline: \(names)."
    }
}
