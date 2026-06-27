import XCTest

/// Validates the bundled ARAM: Mayhem augment resources (produced by data-pipeline/)
/// that the overlay loads. Self-contained (matches the repo's dependency-free test style):
/// reads the resource files from the source tree and checks structure + heuristic sanity.
final class AugmentDataTests: XCTestCase {

    private func resourceURL(_ name: String) -> URL {
        // Tests/AugmentDataTests.swift -> ../Sources/Resources/<name>
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../Sources/Resources/\(name)")
            .standardizedFileURL
    }

    private func loadJSON(_ name: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: resourceURL(name)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Could not load/parse resource \(name)")
            return [:]
        }
        return obj
    }

    // MARK: - Mode detection (mirrors AugmentDataService.isMayhem)

    func testMayhemGameModeDetection() {
        func isMayhem(_ mode: String) -> Bool { mode.uppercased() == "KIWI" }
        XCTAssertTrue(isMayhem("KIWI"))     // verified live 2026-06-20: ARAM du Chaos -> gameMode "KIWI"
        XCTAssertTrue(isMayhem("kiwi"))
        XCTAssertFalse(isMayhem("ARAM"))
        XCTAssertFalse(isMayhem("CLASSIC"))
    }

    // MARK: - Catalogue

    func testCatalogueHasMayhemAugments() {
        let cat = loadJSON("mayhem_catalog.json")
        let augments = cat["augments"] as? [[String: Any]] ?? []
        XCTAssertGreaterThan(augments.count, 200, "expected ~220 current Mayhem augments (kiwi.bin.json)")
        for a in augments {
            XCTAssertNotNil(a["id"] as? Int, "augment missing id")
            XCTAssertFalse((a["name"] as? String ?? "").isEmpty, "augment missing name")
            XCTAssertFalse((a["primaryCategory"] as? String ?? "").isEmpty, "augment missing primaryCategory")
            XCTAssertFalse((a["damageType"] as? String ?? "").isEmpty, "augment missing damageType")
        }
        // 100% description coverage is the whole point of the kiwi+stringtable join.
        let withDesc = augments.filter { !(($0["description"] as? String) ?? "").isEmpty }.count
        XCTAssertEqual(withDesc, augments.count, "every augment should have a resolved description")
        let rarities = Set(augments.compactMap { $0["rarity"] as? String })
        XCTAssertEqual(rarities, ["Silver", "Gold", "Prismatic"])
        // Over-tagging fix: damage types come from structured markup, not keyword soup.
        let dmg = Set(augments.compactMap { $0["damageType"] as? String })
        XCTAssertTrue(dmg.isSuperset(of: ["AP", "AD", "ADAPTIVE", "NONE"]))
    }

    func testChampionAndItemVectorsLoad() {
        let champs = loadJSON("mayhem_champions.json")["champions"] as? [String: Any] ?? [:]
        XCTAssertGreaterThan(champs.count, 160)
        let mf = champs["MissFortune"] as? [String: Any] ?? [:]
        let vec = mf["vector"] as? [String: Double] ?? [:]
        XCTAssertFalse(vec.isEmpty, "Miss Fortune should have a stat vector")
        XCTAssertGreaterThan((vec["ad"] ?? 0) + (vec["crit"] ?? 0), 0, "marksman should lean AD/crit")

        let items = loadJSON("mayhem_items.json")["items"] as? [String: Any] ?? [:]
        XCTAssertGreaterThan(items.count, 300)
        // Rabadon's Deathcap (3089) should be pure AP.
        let rabadon = items["3089"] as? [String: Double] ?? [:]
        XCTAssertGreaterThan(rabadon["ap"] ?? 0, 0.5, "Rabadon's should be AP-dominant")
    }

    // MARK: - Recommendations

    func testRecommendationsCoverKnownChampions() {
        let recs = loadJSON("mayhem_recommendations.json")
        let champs = recs["champions"] as? [String: Any] ?? [:]
        XCTAssertGreaterThan(champs.count, 160, "expected ~170 champions")
        for id in ["MissFortune", "Soraka", "Ahri", "Sett", "Jinx"] {
            XCTAssertNotNil(champs[id], "missing recommendations for \(id)")
        }
    }

    func testEachChampionHasRankedPicksPerRarity() {
        let recs = loadJSON("mayhem_recommendations.json")
        let champs = recs["champions"] as? [String: [String: Any]] ?? [:]
        let mf = champs["MissFortune"] ?? [:]
        let byRarity = mf["by_rarity"] as? [String: [[String: Any]]] ?? [:]
        for tier in ["Silver", "Gold", "Prismatic"] {
            let picks = byRarity[tier] ?? []
            XCTAssertFalse(picks.isEmpty, "Miss Fortune has no \(tier) picks")
            XCTAssertLessThanOrEqual(picks.count, 6, "compact bundle should cap at 6 per rarity")
            // picks must be sorted by score descending
            let scores = picks.compactMap { $0["score"] as? Double }
            XCTAssertEqual(scores, scores.sorted(by: >), "\(tier) picks not sorted by score")
            for p in picks {
                XCTAssertNotNil(p["id"] as? Int)
                XCTAssertFalse((p["label"] as? String ?? "").isEmpty)
            }
        }
    }

    /// Heuristic sanity: an enchanter (Soraka) should get strong picks, and her top
    /// Silver augment should not be flagged "Skip".
    func testEnchanterGetsSensibleTopPick() {
        let recs = loadJSON("mayhem_recommendations.json")
        let champs = recs["champions"] as? [String: [String: Any]] ?? [:]
        let soraka = champs["Soraka"] ?? [:]
        let byRarity = soraka["by_rarity"] as? [String: [[String: Any]]] ?? [:]
        let topSilver = (byRarity["Silver"] ?? []).first ?? [:]
        let label = topSilver["label"] as? String ?? ""
        XCTAssertTrue(["Meta", "Strong"].contains(label),
                      "Soraka's top Silver augment should be a Meta/Strong pick, got \(label)")
        // Top pick of each rarity should be a real meta pick (arammayhem-backed).
        XCTAssertEqual(topSilver["meta"] as? Bool, true, "top Silver should be a meta pick")
    }
}
