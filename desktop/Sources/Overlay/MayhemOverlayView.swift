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
    static func tierGrade(_ t: Int) -> String { ["S", "A", "B", "C", "D"][max(0, min(4, t - 1))] }
    static func tierColor(_ t: Int) -> Color {   // Blitz Mayhem tier palette: S gold · A teal · B blue · C grey · D red
        switch t {
        case 1: return hex(0xE6A23C)
        case 2: return hex(0x37CFBE)
        case 3: return hex(0x4F8FE6)
        case 4: return hex(0x8B90A0)
        default: return hex(0xC07272)
        }
    }
    static let topLitStroke = LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom)
}

/// Downward-pointing shield/pennant — the shape Blitz uses for its augment tier badges.
struct MAShield: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.6))
        p.addLine(to: CGPoint(x: w * 0.5, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.6))
        p.closeSubpath()
        return p
    }
}

/// Blitz-style augment tier badge (S/A/B/C/D), colored shield on the augment icon's corner.
struct MATierBadge: View {
    let tier: Int
    var size: CGFloat = 15
    var body: some View {
        let c = MA.tierColor(tier)
        ZStack {
            MAShield().fill(c)
            MAShield().stroke(.black.opacity(0.35), lineWidth: 0.5)
            Text(MA.tierGrade(tier))
                .font(.system(size: size * 0.62, weight: .black, design: .rounded))
                .foregroundStyle(MA.base)
                .offset(y: -size * 0.06)
        }
        .frame(width: size, height: size * 1.2)
        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
    }
}

struct MayhemOverlayView: View {
    @ObservedObject var gameStateManager: GameStateManager

    private var champ: String { gameStateManager.activeChampionName }
    private var version: String { gameStateManager.dataDragonVersion }
    private var svc: AugmentDataService { .shared }

    private var groups: [(rarity: MayhemRarity, picks: [AugmentDataService.ScoredAugment])] {
        svc.recommend(championName: champ, itemIDs: gameStateManager.activeItemIDs, perRarity: 4).filter { !$0.picks.isEmpty }
    }
    /// The single best pick: prefer a meta augment that fits the live build, else top meta, else top.
    private var hero: AugmentDataService.ScoredAugment? {
        // The single best augment overall: lowest Blitz tier, then highest win rate.
        groups.flatMap { $0.picks }.min { a, b in
            let ta = a.tier ?? 9, tb = b.tier ?? 9
            if ta != tb { return ta < tb }
            return (a.wr ?? 0) > (b.wr ?? 0)
        }
    }
    private var build: BlitzBuilds.BlitzBuild? { svc.build(forChampionName: champ) }

    /// Live overlay caps content to this height and scrolls past it (keeps it off the minimap);
    /// nil renders the full panel (used by the PNG preview).
    var maxHeight: CGFloat? = nil

    var body: some View {
        Group {
            if let mh = maxHeight {
                MAHeightCapped(maxHeight: mh) { contentBody }
            } else {
                contentBody
            }
        }
        .frame(width: 408)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MA.base.opacity(0.94)))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MA.topLitStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            MAChampionHeader(name: champ, version: version, kda: gameStateManager.kda, level: gameStateManager.playerLevel, tier: build?.tier)

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
                    let rows = group.picks.filter { $0.augment.id != heroId }.prefix(3)
                    if !rows.isEmpty {
                        if idx > 0 { Spacer().frame(height: 14) }
                        MARarityBand(rarity: group.rarity, picks: Array(rows), version: version)
                    }
                }
                if let b = build {
                    Spacer().frame(height: 10)
                    Rectangle().fill(MA.hairline).frame(height: 1)
                    Spacer().frame(height: 8)
                    MABuildRegion(build: b, version: version, owned: Set(gameStateManager.activeItemIDs.map { $0 % 100000 }))
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(width: 408)
    }
}

/// Caps its content to `maxHeight`; if the content is taller it becomes scrollable, otherwise the
/// frame shrinks to fit. Keeps the tall Mayhem panel from overrunning the minimap.
private struct MAHeightCapped<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var measured: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: measured > maxHeight) {
            content.background(GeometryReader { g in
                Color.clear.preference(key: MAHeightKey.self, value: g.size.height)
            })
        }
        .frame(height: measured == 0 ? maxHeight : min(measured, maxHeight))
        .scrollDisabled(measured <= maxHeight)
        .onPreferenceChange(MAHeightKey.self) { measured = $0 }
    }
}

private struct MAHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Header (glass chrome)

struct MAChampionHeader: View {
    let name: String, version: String
    let kda: (kills: Int, deaths: Int, assists: Int)
    let level: Int
    var tier: Int? = nil   // champion's Mayhem standing — shown as a shield on the portrait, like Blitz

    /// Riot marketing patch (DataDragon 16.13 → 26.13) for parity with Blitz's patch label.
    private var subtitle: String {
        let p = version.split(separator: ".")
        guard p.count >= 2, let major = Int(p[0]) else { return "ARAM · MAYHEM" }
        return "ARAM · MAYHEM · \(major + 10).\(p[1])"
    }

    var body: some View {
        HStack(spacing: 12) {
            ChampionIcon(name: name.isEmpty ? "" : name, version: version, size: 40)
                .overlay(alignment: .bottomLeading) {
                    if let t = tier { MATierBadge(tier: t, size: 15).offset(x: -4, y: 4) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "ARAM Mayhem" : name)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(MA.textPrimary)
                Text(subtitle).font(MA.mono(10, .medium)).tracking(0.8).foregroundStyle(MA.textSecondary)
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

    private var fits: Bool { scored.reason.hasPrefix("Matches") }
    private var pivot: Bool { scored.reason.hasPrefix("Build-defining") }

    var body: some View {
        HStack(spacing: 14) {
            AugmentIcon(url: scored.augment.iconUrl.isEmpty ? nil : URL(string: scored.augment.iconUrl), size: 52)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(MA.gold.opacity(0.55), lineWidth: 1))
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(MA.gold.opacity(0.26)).blur(radius: 22).padding(-10).allowsHitTesting(false))
                .overlay(alignment: .bottomLeading) {
                    if let t = scored.tier { MATierBadge(tier: t, size: 17).offset(x: -5, y: 5) }
                }
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
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MA.hero))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MA.topLitStroke, lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(MA.gold).frame(width: 5).padding(.vertical, 6)
        }
        .overlay(alignment: .topTrailing) {
            Text("● BEST").font(MA.mono(9, .semibold)).tracking(1).foregroundStyle(MA.gold).padding(.top, 7).padding(.trailing, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
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
        let cat = scored.augment.primaryCategory.replacingOccurrences(of: "-", with: " · ")  // Offense-AS → Offense · AS
        return dmg != nil ? "\(cat) · \(dmg!)" : cat
    }

    var body: some View {
        HStack(spacing: 11) {
            AugmentIcon(url: scored.augment.iconUrl.isEmpty ? nil : URL(string: scored.augment.iconUrl), size: 32)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .saturation(scored.meta ? 1 : 0.85)
                .overlay(alignment: .bottomLeading) {
                    if let t = scored.tier { MATierBadge(tier: t, size: 14).offset(x: -4, y: 4) }
                }
                .overlay(alignment: .topTrailing) {
                    if fits {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(MA.ahead)
                            .background(Circle().fill(MA.base)).offset(x: 4, y: -4)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(scored.augment.name).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(scored.meta ? MA.textBody : MA.textSecondary).lineLimit(1)
                Text(glyph).font(MA.mono(9)).foregroundStyle(MA.textMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(scored.wr.map { "\(Int($0.rounded()))%" } ?? "–")
                .font(MA.mono(13, .medium)).monospacedDigit()
                .foregroundStyle(scored.wr == nil ? MA.textFaint : MA.wr((scored.wr ?? 0).rounded()))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.leading, 10).padding(.trailing, 14)
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
        VStack(alignment: .leading, spacing: 5) {
            // C0 build identity — names the dominant playstyle build being shown (Tank/AP/Crit…)
            if let arch = build.archetype, !arch.isEmpty {
                HStack(spacing: 6) {
                    Text("BUILD").font(MA.mono(9, .medium)).tracking(1).foregroundStyle(MA.textMuted)
                    Text(arch.uppercased()).font(MA.mono(9, .bold)).tracking(0.5).foregroundStyle(MA.brass)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MA.brass.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(MA.brass.opacity(0.30), lineWidth: 0.5))
                    Spacer()
                }
            }
            // C1 stat strip
            HStack(spacing: 0) {
                statCell("WIN RATE", String(format: "%.0f%%", build.winRate), MA.textBody)
                divider
                statCell("GAMES", games(build.games), MA.textBody)
                divider
                statCell("SORTS", "", MA.textBody, spells: build.spells)
            }
            // C2 skill priority + full level path
            if !build.skillMax.isEmpty { skillLine }
            if let so = build.skillOrder, !so.isEmpty { skillPath(so) }
            // C3 item path — item/rune chrome gently recedes; stats + skills keep full contrast
            if !build.starting.isEmpty { itemSection("DÉPART", build.starting, 24).opacity(0.9) }
            if !build.core.isEmpty { coreSection.opacity(0.9) }
            if !build.situational.isEmpty { itemSection("SITU.", build.situational, 24).opacity(0.8) }
            // C4 runes
            if let rp = build.runePage, rp.keystone != nil { runesLine(rp).opacity(0.9) }
        }
    }

    private var divider: some View { Rectangle().fill(MA.hairline).frame(width: 1, height: 18) }

    private func statCell(_ label: String, _ value: String, _ color: Color, spells: [Int] = []) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(MA.mono(9, .medium)).tracking(0.8).foregroundStyle(MA.textMuted)
            if !spells.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(spells.prefix(2).enumerated()), id: \.offset) { _, s in
                        AugmentIcon(url: DataDragon.shared.summonerSpellIconURL(id: s, version: version), size: 18)
                    }
                }
                .frame(height: 18)
            } else {
                Text(value).font(MA.mono(14, .semibold)).monospacedDigit().foregroundStyle(color)
                    .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, label == "WIN RATE" ? 0 : 10)
    }

    private var skillLine: some View {
        HStack(spacing: 4) {
            Text("MAX").font(MA.mono(9, .medium)).tracking(0.8).foregroundStyle(MA.textMuted).frame(width: 44, alignment: .leading)
            let letters = build.skillMax.split(separator: ">").map(String.init)
            ForEach(Array(letters.enumerated()), id: \.offset) { i, l in
                Text(l).font(MA.mono(11, .bold)).foregroundStyle(MA.abilityColor(l))
                    .frame(width: 18, height: 18)
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
                itemIcon(id, 24)
                if i < min(build.core.count, 5) - 1 {
                    Image(systemName: "chevron.compact.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.white.opacity(0.25))
                }
            }
        }
    }

    /// Level-by-level skill path (1..18) as tiny ability cells — matches Blitz's skill order grid.
    private func skillPath(_ order: [Int]) -> some View {
        HStack(spacing: 2) {
            Text("ORDRE").font(MA.mono(9, .medium)).tracking(0.8).foregroundStyle(MA.textMuted)
                .frame(width: 44, alignment: .leading)
            ForEach(Array(order.prefix(18).enumerated()), id: \.offset) { _, s in
                let l = ["", "Q", "W", "E", "R"][min(max(s, 0), 4)]
                Text(l).font(MA.mono(7, .bold)).foregroundStyle(MA.abilityColor(l))
                    .frame(width: 13, height: 13)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(MA.abilityColor(l).opacity(0.14)))
            }
        }
    }

    /// Recommended rune page: keystone + 3 primary, secondary tree + 2, then 3 stat shards.
    private func runesLine(_ rp: BlitzBuilds.BlitzBuild.RunePage) -> some View {
        HStack(spacing: 5) {
            Text("RUNES").font(MA.mono(9, .medium)).tracking(0.8).foregroundStyle(MA.textMuted)
                .frame(width: 44, alignment: .leading)
            if let ks = rp.keystone { runeIcon(ks, 24, ring: MA.brass) }
            ForEach(Array(rp.primary.prefix(3).enumerated()), id: \.offset) { _, r in runeIcon(r, 17) }
            Rectangle().fill(MA.hairline).frame(width: 1, height: 18)
            if let st = rp.secondaryTree { runeIcon(st, 14) }
            ForEach(Array(rp.secondary.prefix(2).enumerated()), id: \.offset) { _, r in runeIcon(r, 17) }
            Rectangle().fill(MA.hairline).frame(width: 1, height: 18)
            ForEach(Array(rp.shards.prefix(3).enumerated()), id: \.offset) { _, r in runeIcon(r, 11) }
            Spacer(minLength: 0)
        }
    }

    private func runeIcon(_ id: Int, _ size: CGFloat, ring: Color? = nil) -> some View {
        AugmentIcon(url: AugmentDataService.shared.runeIconURL(id), size: size)
            .clipShape(Circle())
            .overlay(ring.map { Circle().strokeBorder($0.opacity(0.5), lineWidth: 1) })
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
