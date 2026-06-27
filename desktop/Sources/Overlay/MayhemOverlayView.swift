import SwiftUI

// ATELIER — world-class ARAM: Mayhem overlay. Warm-navy machined sheet, glass only on the header,
// one gold hero card for the single best pick, rarity bands with aligned WR/fit columns, and the
// full Blitz build below a hairline. Gold is used exactly once per render (the hero).

enum MA {
    static func hex(_ h: UInt) -> Color {
        Color(red: Double((h >> 16) & 0xff) / 255, green: Double((h >> 8) & 0xff) / 255, blue: Double(h & 0xff) / 255)
    }
    static let base = hex(0x08081A), surface = hex(0x12122A), hero = hex(0x15152E)
    static let gold = hex(0xC8AA6E), prismatic = hex(0x7FD2E6), brass = hex(0xB79A63), silver = hex(0x8A8A98)
    static let ahead = hex(0x4ADE80), warn = hex(0xFACC15)
    static let qBlue = hex(0x60A5FA), wRed = hex(0xF87171), eGreen = hex(0x4ADE80)
    static let textPrimary = hex(0xF2F0EA), textBody = hex(0xE4E2DA), textSecondary = hex(0x9A98A8)
    static let textMuted = hex(0x6E6E80), textFaint = hex(0x545463)
    static let hairline = Color.white.opacity(0.06)

    static func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .monospaced) }
    static func wr(_ x: Double) -> Color { x >= 52 ? ahead : (x <= 48 && x > 0 ? warn : textSecondary) }
    static func rarityColor(_ r: String) -> Color {
        switch r { case "Prismatic": return prismatic; case "Gold": return brass; default: return silver }
    }
    static func abilityColor(_ l: String) -> Color {
        switch l { case "Q": return qBlue; case "W": return wRed; case "E": return eGreen; default: return textSecondary }
    }
    static let topLitStroke = LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom)
}

struct MayhemOverlayView: View {
    @ObservedObject var gameStateManager: GameStateManager

    private var champ: String { gameStateManager.activeChampionName }
    private var version: String { gameStateManager.dataDragonVersion }
    private var svc: AugmentDataService { .shared }

    private var groups: [(rarity: MayhemRarity, picks: [AugmentDataService.ScoredAugment])] {
        svc.recommend(championName: champ, itemIDs: gameStateManager.activeItemIDs, perRarity: 3).filter { !$0.picks.isEmpty }
    }
    /// The single best pick: prefer a meta augment that fits the live build, else top meta, else top.
    private var hero: AugmentDataService.ScoredAugment? {
        let all = groups.flatMap { $0.picks }
        return all.filter { $0.meta && $0.reason.hasPrefix("Matches") }.max { ($0.wr ?? 0) < ($1.wr ?? 0) }
            ?? all.first { $0.meta } ?? all.first
    }
    private var build: BlitzBuilds.BlitzBuild? { svc.build(forChampionName: champ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MAChampionHeader(name: champ, version: version, kda: gameStateManager.kda, level: gameStateManager.playerLevel)

            if champ.isEmpty {
                Text("En attente de la partie…")
                    .font(.system(size: 12)).foregroundStyle(MA.textMuted)
                    .padding(.top, 14)
            } else {
                let heroId = hero?.augment.id
                if let h = hero {
                    Spacer().frame(height: 14)
                    HeroAugmentCard(scored: h, version: version)
                    Spacer().frame(height: 20)
                }
                ForEach(Array(groups.enumerated()), id: \.element.rarity) { idx, group in
                    let rows = group.picks.filter { $0.augment.id != heroId }.prefix(2)
                    if !rows.isEmpty {
                        if idx > 0 { Spacer().frame(height: 14) }
                        MARarityBand(rarity: group.rarity, picks: Array(rows), version: version)
                    }
                }
                if let b = build {
                    Spacer().frame(height: 14)
                    Rectangle().fill(MA.hairline).frame(height: 1)
                    Spacer().frame(height: 12)
                    MABuildRegion(build: b, version: version, owned: Set(gameStateManager.activeItemIDs.map { $0 % 100000 }))
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(width: 408)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MA.base.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MA.topLitStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
    }
}

// MARK: - Header (glass chrome)

struct MAChampionHeader: View {
    let name: String, version: String
    let kda: (kills: Int, deaths: Int, assists: Int)
    let level: Int

    var body: some View {
        HStack(spacing: 12) {
            ChampionIcon(name: name.isEmpty ? "" : name, version: version, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "ARAM Mayhem" : name)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(MA.textPrimary)
                Text("ARAM · MAYHEM").font(MA.mono(10, .medium)).tracking(0.8).foregroundStyle(MA.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(kda.kills)/\(kda.deaths)/\(kda.assists)")
                    .font(MA.mono(13, .medium)).monospacedDigit().foregroundStyle(MA.textBody)
                Text("LV \(level)").font(MA.mono(10)).monospacedDigit().foregroundStyle(MA.textSecondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(MA.topLitStroke, lineWidth: 1))
    }
}

// MARK: - Hero card (the one gold element)

struct HeroAugmentCard: View {
    let scored: AugmentDataService.ScoredAugment
    let version: String
    @State private var pulse = false

    private var fits: Bool { scored.reason.hasPrefix("Matches") }
    private var pivot: Bool { scored.reason.hasPrefix("Build-defining") }

    var body: some View {
        HStack(spacing: 14) {
            AugmentIcon(url: scored.augment.iconUrl.isEmpty ? nil : URL(string: scored.augment.iconUrl), size: 52)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(MA.gold.opacity(0.55), lineWidth: 1))
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(MA.gold.opacity(0.26)).blur(radius: 22).padding(-10).allowsHitTesting(false))
            VStack(alignment: .leading, spacing: 4) {
                Text(scored.augment.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(MA.textPrimary).lineLimit(1)
                Text(scored.augment.description).font(.system(size: 11)).foregroundStyle(MA.textSecondary).lineLimit(2)
                HStack(spacing: 6) {
                    if fits {
                        Label("Fits", systemImage: "checkmark.seal.fill").font(MA.mono(9, .medium)).foregroundStyle(MA.ahead)
                    }
                    if pivot {
                        Text("PIVOT").font(MA.mono(9, .semibold)).foregroundStyle(MA.warn)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(MA.warn.opacity(0.5), lineWidth: 1))
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                if let wr = scored.wr {
                    Text("\(Int(wr.rounded()))%").font(MA.mono(22, .semibold)).monospacedDigit().foregroundStyle(MA.gold)
                    Text("WR").font(MA.mono(9)).foregroundStyle(MA.textMuted)
                }
            }
            .padding(.trailing, 14)   // snap hero WR right-edge onto the augment-row WR column (x=362)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MA.hero))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MA.topLitStroke, lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(MA.gold).frame(width: 5).padding(.vertical, 6).opacity(pulse ? 1 : 0.85)
        }
        .overlay(alignment: .topTrailing) {
            Text("● BEST").font(MA.mono(9, .semibold)).tracking(1).foregroundStyle(MA.gold).padding(.top, 7).padding(.trailing, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - Rarity band + rows

struct MARarityBand: View {
    let rarity: MayhemRarity
    let picks: [AugmentDataService.ScoredAugment]
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rarity.rawValue.uppercased()).font(MA.mono(10, .semibold)).tracking(1.2)
                .foregroundStyle(MA.rarityColor(rarity.rawValue))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(picks, id: \.augment.id) { MAAugmentRow(scored: $0, rarity: rarity, version: version) }
            }
        }
    }
}

struct MAAugmentRow: View {
    let scored: AugmentDataService.ScoredAugment
    let rarity: MayhemRarity
    let version: String

    private var fits: Bool { scored.reason.hasPrefix("Matches") }
    private var glyph: String {
        let d = scored.augment.damageType
        let dmg = d == "AD" ? "AD" : d == "AP" ? "AP" : d == "ADAPTIVE" ? "Adaptive" : nil
        return dmg != nil ? "\(scored.augment.primaryCategory) · \(dmg!)" : scored.augment.primaryCategory
    }

    var body: some View {
        HStack(spacing: 11) {
            AugmentIcon(url: scored.augment.iconUrl.isEmpty ? nil : URL(string: scored.augment.iconUrl), size: 32)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MA.rarityColor(rarity.rawValue).opacity(0.5), lineWidth: 1))
                .saturation(scored.meta ? 1 : 0.85)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if scored.meta {
                        Image(systemName: "star.fill").font(.system(size: 7)).foregroundStyle(MA.brass)
                    }
                    Text(scored.augment.name).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(scored.meta ? MA.textBody : MA.textSecondary).lineLimit(1)
                }
                Text(glyph).font(MA.mono(9)).foregroundStyle(MA.textMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(scored.wr.map { "\(Int($0.rounded()))%" } ?? "\u{2007}\u{2007}–")
                .font(MA.mono(13, .medium)).monospacedDigit()
                .foregroundStyle(MA.wr((scored.wr ?? 0).rounded())).frame(width: 64, alignment: .trailing)
            Group {
                if fits { Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(MA.ahead) }
            }.frame(width: 20, alignment: .leading)
        }
        .padding(.leading, 10).padding(.trailing, 8)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MA.surface.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(MA.topLitStroke, lineWidth: 1))
        .overlay(alignment: .leading) { Rectangle().fill(MA.rarityColor(rarity.rawValue)).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Build region (Blitz build, recedes to 0.72)

struct MABuildRegion: View {
    let build: BlitzBuilds.BlitzBuild
    let version: String
    let owned: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // C1 stat strip
            HStack(spacing: 0) {
                statCell("WIN RATE", String(format: "%.0f%%", build.winRate), MA.textBody)
                divider
                statCell("GAMES", games(build.games), MA.textBody)
                divider
                statCell("SORTS", "", MA.textBody, spells: build.spells)
            }
            // C2 skill order
            if !build.skillMax.isEmpty { skillLine }
            // C3 item path
            if !build.starting.isEmpty { itemSection("DÉPART", build.starting, 24) }
            if !build.core.isEmpty { coreSection }
            if !build.situational.isEmpty { itemSection("SITU.", build.situational, 22).opacity(0.85) }
        }
        .opacity(0.72)
    }

    private var divider: some View { Rectangle().fill(MA.hairline).frame(width: 1, height: 22) }

    private func statCell(_ label: String, _ value: String, _ color: Color, spells: [Int] = []) -> some View {
        VStack(spacing: 2) {
            Text(label).font(MA.mono(9, .medium)).tracking(0.8).foregroundStyle(MA.textMuted)
            if spells.isEmpty {
                Text(value).font(MA.mono(15, .semibold)).monospacedDigit().foregroundStyle(color)
                    .frame(height: 18)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(spells.prefix(2).enumerated()), id: \.offset) { _, s in
                        AugmentIcon(url: DataDragon.shared.summonerSpellIconURL(id: s, version: version), size: 18)
                    }
                }
                .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var skillLine: some View {
        HStack(spacing: 4) {
            Text("MAX").font(MA.mono(9, .medium)).tracking(0.8).foregroundStyle(MA.textMuted).frame(width: 44, alignment: .leading)
            let letters = build.skillMax.split(separator: ">").map(String.init)
            ForEach(Array(letters.enumerated()), id: \.offset) { i, l in
                Text(l).font(MA.mono(12, .bold)).foregroundStyle(MA.abilityColor(l))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(MA.abilityColor(l).opacity(0.12)))
                if i < letters.count - 1 {
                    Image(systemName: "chevron.compact.right").font(.system(size: 8, weight: .bold)).foregroundStyle(MA.textFaint)
                }
            }
        }
    }

    private func itemSection(_ label: String, _ ids: [Int], _ size: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(label).font(MA.mono(9, .medium)).tracking(0.8).foregroundStyle(MA.textMuted).frame(width: 44, alignment: .leading)
            ForEach(Array(ids.prefix(5).enumerated()), id: \.offset) { _, id in
                itemIcon(id, size)
            }
        }
    }

    private var coreSection: some View {
        HStack(spacing: 4) {
            Text("CORE").font(MA.mono(9, .semibold)).tracking(0.8).foregroundStyle(MA.textMuted).frame(width: 44, alignment: .leading)
            ForEach(Array(build.core.prefix(5).enumerated()), id: \.offset) { i, id in
                itemIcon(id, 30)
                if i < min(build.core.count, 5) - 1 {
                    Image(systemName: "chevron.compact.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.white.opacity(0.25))
                }
            }
        }
    }

    private func itemIcon(_ id: Int, _ size: CGFloat) -> some View {
        let has = owned.contains(id % 100000)
        return AugmentIcon(url: DataDragon.shared.itemIconURL(id: id, version: version), size: size)
            .saturation(owned.isEmpty ? 1 : (has ? 1 : 0.4))
            .opacity(owned.isEmpty ? 1 : (has ? 1 : 0.6))
            .overlay(has && !owned.isEmpty ? RoundedRectangle(cornerRadius: 4).strokeBorder(MA.brass.opacity(0.7), lineWidth: 1) : nil)
    }

    private func games(_ g: Int) -> String {
        g >= 1000 ? String(format: "%.1fk", Double(g) / 1000) : "\(g)"
    }
}
