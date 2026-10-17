import SwiftUI

struct OverlayView: View {
    @ObservedObject var gameStateManager: GameStateManager

    @AppStorage("overlayOpacity") private var overlayOpacity: Double = 0.75

    private var isMayhem: Bool {
        AugmentDataService.isMayhem(gameMode: gameStateManager.gameMode)
    }

    @ViewBuilder var body: some View {
        if isMayhem {
            // ARAM: Mayhem ("ARAM du Chaos") — the ATELIER layout (its own card chrome).
            // Cap to ~86% of the screen so the tall panel scrolls instead of overrunning the minimap.
            MayhemOverlayView(gameStateManager: gameStateManager,
                              maxHeight: (NSScreen.main?.visibleFrame.height ?? 1000) * 0.86)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                PlayerStatsSection(gameStateManager: gameStateManager)
                GoldScoreboard(
                    allyTeamGold: gameStateManager.allyTeamGold,
                    enemyTeamGold: gameStateManager.enemyTeamGold,
                    matchups: gameStateManager.laneMatchups,
                    version: gameStateManager.dataDragonVersion
                )
                SpellTrackerSection(gameStateManager: gameStateManager)
            }
            .padding(16)
            .frame(width: 408)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 10/255, green: 10/255, blue: 26/255).opacity(overlayOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

// MARK: - CS Tracker

struct PlayerStatsSection: View {
    @ObservedObject var gameStateManager: GameStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // KDA header
            HStack(alignment: .firstTextBaseline) {
                Text("\(gameStateManager.kda.kills)/\(gameStateManager.kda.deaths)/\(gameStateManager.kda.assists)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer()

                Text("Lv\(gameStateManager.playerLevel)")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.lolGold)
            }

            // Stats grid
            HStack(spacing: 16) {
                StatItem(
                    label: "CS/min",
                    value: String(format: "%.1f", gameStateManager.csPerMin),
                    sub: "\(gameStateManager.currentCS) cs"
                )
                StatItem(
                    label: "Gold/min",
                    value: String(format: "%.0f", gameStateManager.goldPerMin),
                    sub: nil
                )
                StatItem(
                    label: "KP",
                    value: String(format: "%.0f%%", gameStateManager.killParticipation),
                    sub: nil
                )
                StatItem(
                    label: "Vision/min",
                    value: String(format: "%.1f", gameStateManager.visionPerMin),
                    sub: nil
                )
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let sub: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.lolTextSecondary)
            if let sub = sub {
                Text(sub)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.lolTextSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Spell Tracker

struct SpellTrackerSection: View {
    @ObservedObject var gameStateManager: GameStateManager

    private var version: String { gameStateManager.dataDragonVersion }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "ENEMY SPELLS (click to track)")

            ForEach(Array(gameStateManager.enemySpells.enumerated()), id: \.element.id) { index, enemy in
                HStack(spacing: 8) {
                    // Champion icon + name
                    ChampionIcon(name: enemy.championName, version: version, size: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(enemy.championName.prefix(9))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Lv\(enemy.level)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.lolTextSecondary)
                    }
                    .frame(width: 75, alignment: .leading)

                    Spacer()

                    // Ult
                    SpellBadge(spell: enemy.ult, label: "R", iconURL: nil, size: .large) {
                        gameStateManager.markUltUsed(enemyIndex: index)
                    }

                    // Summoner spells with icons
                    SpellBadge(
                        spell: enemy.spell1,
                        label: nil,
                        iconURL: DataDragon.shared.spellIconURL(rawDisplayName: enemy.spell1.rawDisplayName ?? "", version: version),
                        size: .medium
                    ) {
                        gameStateManager.markSpellUsed(enemyIndex: index, spellIndex: 0)
                    }

                    SpellBadge(
                        spell: enemy.spell2,
                        label: nil,
                        iconURL: DataDragon.shared.spellIconURL(rawDisplayName: enemy.spell2.rawDisplayName ?? "", version: version),
                        size: .medium
                    ) {
                        gameStateManager.markSpellUsed(enemyIndex: index, spellIndex: 1)
                    }
                }
            }
        }
    }
}

// MARK: - Champion Icon

struct ChampionIcon: View {
    let name: String
    let version: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: DataDragon.shared.championIconURL(name: name, version: version)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            case .failure:
                fallbackIcon
            case .empty:
                fallbackIcon
            @unknown default:
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
    }

    private var fallbackIcon: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(white: 0.15))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(2)))
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            )
    }
}

struct SpellBadge: View {
    let spell: SpellCooldownState
    var label: String?
    var iconURL: URL?
    var size: BadgeSize = .medium
    let onTap: () -> Void

    enum BadgeSize {
        case small, medium, large
        var dimension: CGFloat {
            switch self {
            case .small: return 28
            case .medium: return 34
            case .large: return 38
            }
        }
        var fontSize: CGFloat {
            switch self {
            case .small: return 11
            case .medium: return 13
            case .large: return 15
            }
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background: icon or solid color
                if spell.isReady, let url = iconURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(backgroundColor)
                        }
                    }
                } else if spell.isReady && label == "R" {
                    Rectangle().fill(Color.lolGold.opacity(0.9))
                } else if spell.isReady {
                    Rectangle().fill(Color.lolGreen)
                } else {
                    Rectangle().fill(Color(white: 0.1))
                }

                // Cooldown overlay
                if !spell.isReady {
                    Color.black.opacity(0.7)
                    Text(cooldownText)
                        .font(.system(size: size.fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.lolRed)
                } else if label != nil {
                    Text(label!)
                        .font(.system(size: size.fontSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: size.dimension, height: size.dimension)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(spell.isReady ? Color.clear : Color.lolRed.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var cooldownText: String {
        guard let end = spell.cooldownEnd else { return "" }
        let remaining = Int(end.timeIntervalSinceNow)
        if remaining <= 0 { return "" }
        return "\(remaining)"
    }

    private var backgroundColor: Color {
        if spell.isReady {
            return label == "R" ? Color.lolGold.opacity(0.9) : Color.lolGreen
        }
        return Color(white: 0.1)
    }
}

// MARK: - Ally Tracker

struct AllyTrackerSection: View {
    let allies: [AllyState]

    var body: some View {
        if !allies.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "TEAM")

                ForEach(allies) { ally in
                    HStack(spacing: 8) {
                        Text(ally.championName.prefix(10))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ally.isDead ? Color.lolRed.opacity(0.5) : .white.opacity(0.7))
                            .frame(width: 90, alignment: .leading)

                        // Ult indicator
                        Text(ally.ultReady ? "R" : "·")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ally.ultReady ? Color.lolGreen.opacity(0.8) : Color(white: 0.15))
                            )
                            .foregroundStyle(ally.ultReady ? .black : Color(white: 0.3))

                        Text("Lv\(ally.level)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.lolTextSecondary)

                        Spacer()

                        if ally.isDead {
                            Text("DEAD")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.lolRed)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Gold Scoreboard

struct GoldScoreboard: View {
    let allyTeamGold: Int
    let enemyTeamGold: Int
    let matchups: [LaneMatchup]
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "GOLD")

            // Team totals
            HStack {
                Text("Your team")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.lolGreen.opacity(0.8))
                Spacer()
                Text(formatGold(allyTeamGold))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("vs")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lolTextSecondary)
                Text(formatGold(enemyTeamGold))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text("Enemy")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.lolRed.opacity(0.8))
            }

            // Total diff
            let totalDiff = allyTeamGold - enemyTeamGold
            HStack {
                Spacer()
                Text(diffText(totalDiff))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(totalDiff >= 0 ? Color.lolGold : Color.lolRed)
                Spacer()
            }

            // Lane matchups
            if !matchups.isEmpty {
                Divider().background(Color.white.opacity(0.06))

                ForEach(matchups) { lane in
                    HStack(spacing: 5) {
                        // Ally side
                        ChampionIcon(name: lane.allyChampion, version: version, size: 22)
                        Text(formatGold(lane.allyGold))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 40, alignment: .trailing)

                        Spacer()

                        // Diff
                        Text(lane.diffText)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(lane.diff >= 0 ? Color.lolGreen : Color.lolRed)
                            .frame(width: 55)

                        Spacer()

                        // Enemy side
                        Text(formatGold(lane.enemyGold))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 40, alignment: .leading)
                        ChampionIcon(name: lane.enemyChampion, version: version, size: 22)
                    }
                }
            }
        }
    }

    private func formatGold(_ gold: Int) -> String {
        if gold >= 1000 {
            return String(format: "%.1fk", Double(gold) / 1000.0)
        }
        return "\(gold)"
    }

    private func diffText(_ diff: Int) -> String {
        let sign = diff >= 0 ? "+" : ""
        if abs(diff) >= 1000 {
            return String(format: "%@%.1fk gold", sign, Double(diff) / 1000.0)
        }
        return "\(sign)\(diff) gold"
    }

    private func positionEmoji(_ pos: String) -> String {
        switch pos {
        case "TOP": return "🗡"
        case "JUNGLE": return "🌿"
        case "MIDDLE": return "⭐"
        case "BOTTOM": return "🏹"
        case "UTILITY": return "🛡"
        default: return "•"
        }
    }
}

// MARK: - Augment Reference (ARAM: Mayhem)

/// Build-aware augment recommendations for ARAM: Mayhem ("Augment Briefing" layout).
/// Order = real meta (arammayhem). Gold ★ = meta pick; blue "FITS BUILD" chip = synergizes with
/// the live item build. Compliance: qualitative only, NEVER win rates.
struct AugmentReferenceSection: View {
    let championName: String
    let itemIDs: [Int]
    let version: String

    private var groups: [(rarity: MayhemRarity, picks: [AugmentDataService.ScoredAugment])] {
        AugmentDataService.shared.recommend(championName: championName, itemIDs: itemIDs, perRarity: 3)
            .filter { !$0.picks.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AugmentHeader(championName: championName, itemIDs: itemIDs, version: version)
            Divider().background(Color.white.opacity(0.06)).padding(.vertical, 10)

            if championName.isEmpty {
                Text("Waiting for game…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lolTextSecondary)
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.rarity) { idx, group in
                    if idx > 0 { Color.clear.frame(height: 10) }
                    TierSection(rarity: group.rarity, picks: group.picks, isTopTier: idx == 0)
                }
                if let build = AugmentDataService.shared.build(forChampionName: championName) {
                    Color.clear.frame(height: 12)
                    BuildSection(build: build, version: version)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: championName)
    }
}

/// Full Blitz ARAM build: starting items, core item path, situational, spells + skill order.
struct BuildSection: View {
    let build: BlitzBuilds.BlitzBuild
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("BUILD")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color.lolTextSecondary)
                if build.winRate > 0 {
                    Text("\(Int(build.winRate.rounded()))% WR")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.lolTextTertiary)
                }
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            }

            if !build.starting.isEmpty {
                labeledRow("Départ", items: build.starting, size: 20)
            }
            if !build.core.isEmpty {
                corePath(build.core)
            }
            if !build.situational.isEmpty {
                labeledRow("Situ.", items: build.situational, size: 18)
            }

            HStack(spacing: 8) {
                ForEach(Array(build.spells.prefix(2).enumerated()), id: \.offset) { _, sid in
                    AugmentIcon(url: DataDragon.shared.summonerSpellIconURL(id: sid, version: version), size: 18)
                }
                if !build.skillMax.isEmpty {
                    Text(build.skillMax)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.85))
                }
            }
        }
    }

    private func labeledRow(_ label: String, items: [Int], size: CGFloat) -> some View {
        HStack(spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.5)
                .foregroundStyle(Color.lolTextTertiary)
                .frame(width: 44, alignment: .leading)
            ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, id in
                AugmentIcon(url: DataDragon.shared.itemIconURL(id: id, version: version), size: size)
            }
        }
    }

    private func corePath(_ items: [Int]) -> some View {
        HStack(spacing: 4) {
            Text("CORE")
                .font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.5)
                .foregroundStyle(Color.lolGold.opacity(0.8))
                .frame(width: 44, alignment: .leading)
            ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { idx, id in
                AugmentIcon(url: DataDragon.shared.itemIconURL(id: id, version: version), size: 26)
                if idx < min(items.count, 5) - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.lolTextTertiary)
                }
            }
        }
    }
}

struct AugmentHeader: View {
    let championName: String
    let itemIDs: [Int]
    let version: String

    var body: some View {
        HStack(spacing: 9) {
            ChampionIcon(name: championName, version: version, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(championName.isEmpty ? "ARAM: Mayhem" : championName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(white: 0.94))
                Text("AUGMENTS · ARAM MAYHEM")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.lolTextSecondary)
            }
            Spacer()
            if !itemIDs.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(itemIDs.prefix(6).enumerated()), id: \.offset) { _, id in
                        AugmentIcon(url: DataDragon.shared.itemIconURL(id: id, version: version), size: 18)
                    }
                }
            }
        }
    }
}

struct TierSection: View {
    let rarity: MayhemRarity
    let picks: [AugmentDataService.ScoredAugment]
    let isTopTier: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(rarity.rawValue.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(rarity.label)
                Rectangle().fill(rarity.label.opacity(rarity.ruleAlpha)).frame(height: 1)
            }
            ForEach(Array(picks.enumerated()), id: \.element.augment.id) { i, pick in
                AugmentRow(scored: pick, rarity: rarity, isTopPick: isTopTier && i == 0)
            }
        }
    }
}

struct AugmentRow: View {
    let scored: AugmentDataService.ScoredAugment
    let rarity: MayhemRarity
    let isTopPick: Bool

    private var iconURL: URL? {
        scored.augment.iconUrl.isEmpty ? nil : URL(string: scored.augment.iconUrl)
    }

    var body: some View {
        HStack(spacing: 9) {
            AugmentIcon(url: iconURL, size: 26)
            HStack(spacing: 4) {
                if scored.meta {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.lolGold)
                }
                Text(scored.augment.name)
                    .font(.system(size: 12.5, weight: scored.meta ? .semibold : .medium))
                    .foregroundStyle(scored.meta ? Color.lolGold : Color(white: 0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            trailing
        }
        .frame(minHeight: 38)
        .padding(.vertical, 4)
        .padding(.leading, 9)
        .background(isTopPick ? rarity.spine.opacity(0.05) : .clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(rarity.spine).frame(width: 2)
        }
    }

    /// Right column: build-synergy chip (FITS BUILD / PIVOT) + win rate %.
    @ViewBuilder private var trailing: some View {
        HStack(spacing: 6) {
            if let chip = buildChip {
                Text(chip.0)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(chip.1)
            }
            if let wr = scored.wr {
                Text("\(Int(wr.rounded()))%")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.lolTextSecondary)
            } else if buildChip == nil {
                Text(descriptorToken)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.lolTextTertiary)
            }
        }
        .lineLimit(1)
    }

    private var buildChip: (String, Color)? {
        if scored.reason.hasPrefix("Matches your") { return ("FITS BUILD", Color.lolInfo) }
        if scored.reason.hasPrefix("Build-defining") { return ("PIVOT", Color.lolYellow) }
        return nil
    }

    private var descriptorToken: String {
        switch scored.augment.damageType {
        case "AD": return "AD"
        case "AP": return "AP"
        case "ADAPTIVE": return "ADAPT"
        default: return scored.augment.primaryCategory.uppercased()
        }
    }
}

struct AugmentIcon: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            default:
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.15))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Shared Components

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Color.lolTextSecondary)
    }
}

// MARK: - Color Extensions

extension MayhemRarity {
    /// Left accent spine (rarity color; gold reduced so it never competes with the meta ★).
    var spine: Color {
        switch self {
        case .prismatic: return Color(red: 127/255, green: 210/255, blue: 230/255)
        case .gold: return Color.lolGold.opacity(0.55)
        case .silver: return Color.white.opacity(0.16)
        }
    }
    /// Section-header label color.
    var label: Color {
        switch self {
        case .prismatic: return Color(red: 127/255, green: 210/255, blue: 230/255)
        case .gold: return .lolGold
        case .silver: return Color(red: 154/255, green: 154/255, blue: 168/255)
        }
    }
    var ruleAlpha: Double { self == .silver ? 0.14 : 0.16 }
}

extension Color {
    static let lolGold = Color(red: 200/255, green: 170/255, blue: 110/255)        // #c8aa6e
    static let lolGreen = Color(red: 74/255, green: 222/255, blue: 128/255)        // #4ade80
    static let lolRed = Color(red: 248/255, green: 113/255, blue: 113/255)         // #f87171
    static let lolYellow = Color(red: 250/255, green: 204/255, blue: 21/255)       // #facc15
    static let lolInfo = Color(red: 96/255, green: 165/255, blue: 250/255)         // #60a5fa
    static let lolTextSecondary = Color(red: 136/255, green: 136/255, blue: 153/255) // #888899
    static let lolTextTertiary = Color(red: 85/255, green: 85/255, blue: 102/255)  // #555566
    static let lolOverlayBg = Color(red: 26/255, green: 26/255, blue: 46/255)
    static let lolChampSelectBg = Color(red: 22/255, green: 33/255, blue: 62/255)
}
