import Foundation

/// Models for the ARAM: Mayhem ("ARAM du Chaos") augment data, produced by the
/// Python pipeline in `data-pipeline/` and bundled as app resources.
///
/// IMPORTANT (Riot policy): recommendations are a deterministic heuristic (champion
/// identity + live build amplification). They carry NO win rates — Mayhem match data
/// is API-blocked and Riot forbids displaying augment win rates.

/// Shared stat-class space for champions, augments and items.
enum StatDim: String, CaseIterable {
    case ap, ad, crit, on_hit, attack_speed, ah, tank, heal_shield, pen, mana
}

typealias StatVector = [String: Double]

/// Per-champion ranked augment picks (compact bundle: top N per rarity, build-agnostic).
struct MayhemRecommendations: Codable {
    let meta: Meta
    let champions: [String: ChampionRecs]   // keyed by Data Dragon champion id, e.g. "MissFortune"

    struct Meta: Codable {
        let version: String
        let championCount: Int
    }

    struct ChampionRecs: Codable {
        let key: String
        let name: String
        let tags: [String]
        let byRarity: [String: [AugmentPick]]   // "Prismatic" | "Gold" | "Silver"
    }

    struct AugmentPick: Codable {
        let id: Int
        let name: String
        let label: String     // "Meta" (real arammayhem pick) | Strong | Situational
        let score: Double
        let cat: String       // primaryCategory
        let dmg: String       // AD | AP | ADAPTIVE | NONE
        let pivot: Bool
        let meta: Bool        // true = real meta pick (arammayhem), false = heuristic fill
        let wr: Double?       // win rate % (arammayhem), nil when unavailable
    }
}

/// Per-champion full ARAM build from Blitz (datalake.v2.iesdev.com), keyed by Data Dragon id.
struct BlitzBuilds: Codable {
    let builds: [String: BlitzBuild]

    struct BlitzBuild: Codable {
        let winRate: Double
        let games: Int
        let tier: Int?            // 1 (strongest) … 5 (weakest) in Mayhem — champion standing
        let archetype: String?    // dominant playstyle: "Tank" / "AP" / "Crit" / "Bruiser" …

        let starting: [Int]
        let core: [Int]
        let situational: [Int]
        let spells: [Int]
        let skillMax: String      // e.g. "Q>W>E"
        let skillOrder: [Int]?    // level-by-level 1..18 (1=Q,2=W,3=E,4=R)
        let keystone: Int?
        let primaryTree: Int?
        let runePage: RunePage?   // coherent recommended rune page

        struct RunePage: Codable {
            let keystone: Int?
            let primaryTree: Int?
            let primary: [Int]        // 3 primary minor runes
            let secondaryTree: Int?
            let secondary: [Int]      // 2 secondary runes
            let shards: [Int]         // 3 stat shards (offense / flex / defense)
        }
    }
}

/// Full augment catalogue (id → category/damageType/vector/icon/description).
struct MayhemCatalog: Codable {
    let meta: Meta
    let augments: [Augment]

    struct Meta: Codable {
        let version: String
        let augmentCount: Int
    }

    struct Augment: Codable {
        let id: Int
        let apiName: String
        let name: String
        let rarity: String
        let primaryCategory: String
        let damageType: String          // AD | AP | ADAPTIVE | NONE
        let vector: StatVector
        let pivot: Bool
        let pivotDim: String?
        let iconUrl: String
        let description: String
    }
}

/// Per-champion stat vector (for runtime build-aware scoring).
struct MayhemChampions: Codable {
    let champions: [String: ChampVec]
    struct ChampVec: Codable {
        let key: String
        let name: String
        let tags: [String]
        let vector: StatVector
    }
}

/// itemID (string) → stat vector (for the runtime build profile).
struct MayhemItems: Codable {
    let items: [String: StatVector]
}

/// Display order for rarity tiers (highest power first).
enum MayhemRarity: String, CaseIterable {
    case prismatic = "Prismatic"
    case gold = "Gold"
    case silver = "Silver"
}
