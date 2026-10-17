import Foundation
import os

/// Loads the bundled ARAM: Mayhem augment data and produces build-aware recommendations.
///
/// Static data (catalogue, champion vectors, item vectors) is generated per-patch by
/// `data-pipeline/mayhem_pipeline.py`. The build-aware re-ranking runs at runtime from the
/// player's LIVE items (Live Client Data API). No network, no game-process access.
///
/// Compliance: re-ranks the augments using static stat-synergy knowledge + the player's own
/// client state. NO win rates are computed or shown.
final class AugmentDataService: @unchecked Sendable {
    static let shared = AugmentDataService()

    private let logger = Logger(subsystem: "com.macleagueoverlay", category: "AugmentData")

    let recommendations: MayhemRecommendations?     // build-agnostic fallback (compact)
    let catalog: MayhemCatalog?
    let champions: MayhemChampions?
    let items: MayhemItems?
    let buildsData: BlitzBuilds?
    private let runeIconPaths: [Int: String]        // rune/shard id -> CommunityDragon icon path
    private let augmentStatsById: [String: [String: MayhemAugmentStats.AugStat]]  // DDragon id -> augId -> stat
    private static let cdragonBase = "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/"

    struct RuneIcons: Codable { let icons: [String: String] }

    /// Per-champion ARAM: Mayhem augment stats from Blitz (the data behind its tier list).
    struct MayhemAugmentStats: Codable {
        let champions: [String: [String: AugStat]]
        struct AugStat: Codable { let tier: Int; let wr: Double; let pick: Double; let games: Int }
    }

    /// CommunityDragon icon URL for a rune or stat-shard id (nil if unmapped).
    func runeIconURL(_ id: Int) -> URL? {
        guard let path = runeIconPaths[id] else { return nil }
        return URL(string: path.hasPrefix("http") ? path : Self.cdragonBase + path)
    }

    private let byDisplayName: [String: MayhemRecommendations.ChampionRecs]
    private let champByName: [String: MayhemChampions.ChampVec]
    private let augmentsById: [Int: MayhemCatalog.Augment]
    private let idByDisplayName: [String: String]   // champion display name -> Data Dragon id

    /// Internal game-mode codename for ARAM: Mayhem, from the Live Client Data API
    /// `gameData.gameMode` (verified live 2026-06-20).
    static let mayhemGameMode = "KIWI"

    // Scoring weights (research-recommended; tune by feel — no win-rate data to fit against).
    private let wChampion = 0.45
    private let wBuild = 0.40
    private let wPivot = 0.15

    /// SwiftPM's generated `Bundle.module` only looks next to the executable's bundle root (and the
    /// build machine's .build path), so in a packaged Hexlens.app it crashes. Check Contents/Resources first.
    private static let resourceBundle: Bundle = {
        let name = "MacLeagueOverlay_MacLeagueOverlay.bundle"
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name), let b = Bundle(url: url) { return b }
        return Bundle.module
    }()

    init() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        func load<T: Decodable>(_ resource: String, as type: T.Type) -> T? {
            guard let url = Self.resourceBundle.url(forResource: resource, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }

        let recs = load("mayhem_recommendations", as: MayhemRecommendations.self)
        let cat = load("mayhem_catalog", as: MayhemCatalog.self)
        let champs = load("mayhem_champions", as: MayhemChampions.self)
        let itms = load("mayhem_items", as: MayhemItems.self)
        let blds = load("blitz_builds", as: BlitzBuilds.self)
        let runeIcons = load("rune_icons", as: RuneIcons.self)
        let augStats = load("mayhem_augment_stats", as: MayhemAugmentStats.self)
        recommendations = recs; catalog = cat; champions = champs; items = itms; buildsData = blds
        runeIconPaths = Dictionary((runeIcons?.icons ?? [:]).compactMap { k, v in Int(k).map { ($0, v) } },
                                   uniquingKeysWith: { a, _ in a })
        augmentStatsById = augStats?.champions ?? [:]

        byDisplayName = Dictionary((recs?.champions.values ?? [String: MayhemRecommendations.ChampionRecs]().values)
            .map { (Self.normalize($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        champByName = Dictionary((champs?.champions.values ?? [String: MayhemChampions.ChampVec]().values)
            .map { (Self.normalize($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        augmentsById = Dictionary((cat?.augments ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        idByDisplayName = Dictionary((recs?.champions ?? [:]).map { (id, c) in (Self.normalize(c.name), id) },
                                     uniquingKeysWith: { a, _ in a })

        if recs == nil || cat == nil || champs == nil || itms == nil {
            logger.error("Failed to load bundled Mayhem augment data")
        } else {
            logger.info("Loaded Mayhem data: \(cat?.augments.count ?? 0) augments, \(champs?.champions.count ?? 0) champions, \(itms?.items.count ?? 0) items")
        }
    }

    /// Full Blitz ARAM build for a champion (items, spells, skill order, win rate).
    func build(forChampionName name: String) -> BlitzBuilds.BlitzBuild? {
        guard let id = idByDisplayName[Self.normalize(name)] else { return nil }
        return buildsData?.builds[id]
    }

    static func isMayhem(gameMode: String) -> Bool { gameMode.uppercased() == mayhemGameMode }

    func recommendations(forChampionName name: String) -> MayhemRecommendations.ChampionRecs? {
        byDisplayName[Self.normalize(name)]
    }

    func augment(id: Int) -> MayhemCatalog.Augment? { augmentsById[id] }

    // MARK: - Build-aware recommendation

    struct ScoredAugment {
        let augment: MayhemCatalog.Augment
        let meta: Bool          // top-tier (S/A) pick — shown with a marker
        let reason: String      // qualitative "why" chip
        let wr: Double?         // Mayhem win rate % for this champion, nil when unavailable
        let tier: Int?          // Blitz Mayhem tier 1(S)…5(D), nil from fallback source
    }

    /// Build the live stat profile B from the player's current item IDs (normalized).
    func buildProfile(itemIDs: [Int]) -> StatVector {
        guard let items = items?.items else { return [:] }
        var b: StatVector = [:]
        for id in itemIDs {
            // Normalize mode-prefixed Mayhem item IDs (e.g. 124011 -> 4011, map-12 variant).
            for key in [String(id), String(id % 100000), String(id % 10000)] {
                if let v = items[key] { for (k, x) in v { b[k, default: 0] += x }; break }
            }
        }
        return Self.unit(b)
    }

    /// Recommendations per rarity for a champion. Order is the REAL meta (arammayhem, baked into
    /// the bundled recs); the live build only annotates each pick ("matches your X build").
    /// Returns top `perRarity` per rarity tier, ordered Prismatic → Gold → Silver.
    func recommend(championName: String, itemIDs: [Int], perRarity: Int = 3) -> [(rarity: MayhemRarity, picks: [ScoredAugment])] {
        let build = buildProfile(itemIDs: itemIDs)
        let hasBuild = !build.isEmpty

        // Preferred path: Blitz per-champion Mayhem augment tiers (matches blitz.gg's tier list).
        if let id = idByDisplayName[Self.normalize(championName)], let stats = augmentStatsById[id] {
            var out: [(MayhemRarity, [ScoredAugment])] = []
            for tier in MayhemRarity.allCases {
                let ranked = stats.compactMap { (idStr, st) -> (MayhemCatalog.Augment, MayhemAugmentStats.AugStat)? in
                    guard let aid = Int(idStr), let aug = augment(id: aid), aug.rarity == tier.rawValue else { return nil }
                    return (aug, st)
                }
                .filter { $0.1.games >= 150 }                       // drop sub-sample noise
                .sorted { ($0.1.tier, -$0.1.wr) < ($1.1.tier, -$1.1.wr) }  // Blitz tier, then win rate
                let picks = ranked.prefix(perRarity).map { (aug, st) -> ScoredAugment in
                    let cBuild = hasBuild ? Self.cosine(build, aug.vector) : 0
                    let reason = Self.reason(champName: championName, aug: aug, isMeta: st.tier <= 2,
                                             cBuild: cBuild, hasBuild: hasBuild, build: build)
                    return ScoredAugment(augment: aug, meta: st.tier <= 2, reason: reason, wr: st.wr, tier: st.tier)
                }
                out.append((tier, Array(picks)))
            }
            return out
        }

        // Fallback: bundled arammayhem meta order.
        guard let recs = recommendations(forChampionName: championName) else { return [] }
        var out: [(MayhemRarity, [ScoredAugment])] = []
        for tier in MayhemRarity.allCases {
            let picks = (recs.byRarity[tier.rawValue] ?? []).prefix(perRarity).compactMap { pick -> ScoredAugment? in
                guard let aug = augment(id: pick.id) else { return nil }
                let cBuild = hasBuild ? Self.cosine(build, aug.vector) : 0
                let reason = Self.reason(champName: championName, aug: aug, isMeta: pick.meta,
                                         cBuild: cBuild, hasBuild: hasBuild, build: build)
                return ScoredAugment(augment: aug, meta: pick.meta, reason: reason, wr: pick.wr, tier: nil)
            }
            out.append((tier, Array(picks)))
        }
        return out
    }

    /// Qualitative "why" chip. Priority: live build synergy → build-defining pivot → meta/category.
    private static func reason(champName: String, aug: MayhemCatalog.Augment, isMeta: Bool,
                               cBuild: Double, hasBuild: Bool, build: StatVector) -> String {
        if hasBuild, cBuild > 0.3,
           let augTop = aug.vector.max(by: { $0.value < $1.value })?.key {
            let buildTop = build.sorted { $0.value > $1.value }.prefix(2).map { $0.key }
            if buildTop.contains(augTop) {
                return "Matches your \(human(augTop)) build"
            }
        }
        if aug.pivot, let d = aug.pivotDim {
            return "Build-defining → \(human(d))"
        }
        return isMeta ? "Top pick for \(champName)" : descriptor(aug)
    }

    /// Distinct per-augment identity label (its damage type, else its primary category).
    private static func descriptor(_ aug: MayhemCatalog.Augment) -> String {
        switch aug.damageType {
        case "AD": return "Attack Damage"
        case "AP": return "Ability Power"
        case "ADAPTIVE": return "Adaptive"
        default: return aug.primaryCategory
        }
    }

    private static func human(_ dim: String) -> String {
        switch dim {
        case "ap": return "AP"
        case "ad": return "AD"
        case "crit": return "crit"
        case "on_hit": return "on-hit"
        case "attack_speed": return "attack speed"
        case "ah": return "ability haste"
        case "tank": return "tank"
        case "heal_shield": return "heal/shield"
        case "pen": return "penetration"
        case "mana": return "mana"
        default: return dim
        }
    }

    // MARK: - Vector math

    private static func cosine(_ a: StatVector, _ b: StatVector) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var dot = 0.0
        for (k, v) in a { dot += v * (b[k] ?? 0) }
        let na = sqrt(a.values.reduce(0) { $0 + $1 * $1 })
        let nb = sqrt(b.values.reduce(0) { $0 + $1 * $1 })
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na * nb)
    }

    private static func unit(_ v: StatVector) -> StatVector {
        let n = sqrt(v.values.reduce(0) { $0 + $1 * $1 })
        guard n > 0 else { return [:] }
        return v.mapValues { $0 / n }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
