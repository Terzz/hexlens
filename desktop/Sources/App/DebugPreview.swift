import SwiftUI
import AppKit

/// Debug-only: render the augment panel to a PNG for visual QA without a live game.
///   MacLeagueOverlay --render-augment-preview <out.png>
/// Demonstrates build-awareness (same champion with no items vs an AP build).
/// No-op during normal launch. Network icons render as placeholders (synchronous render).
enum DebugPreview {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--render-augment-preview"), idx + 1 < args.count else { return }
        let outPath = args[idx + 1]

        func mock(_ champ: String, _ items: [Int], kda: (Int, Int, Int), lvl: Int) -> GameStateManager {
            let g = GameStateManager()
            g.gameMode = "KIWI"; g.activeChampionName = champ; g.activeItemIDs = items
            g.dataDragonVersion = "16.12.1"; g.kda = kda; g.playerLevel = lvl
            return g
        }
        let content = HStack(alignment: .top, spacing: 24) {
            MayhemOverlayView(gameStateManager: mock("Nidalee", [3089, 3115, 6653], kda: (8, 2, 6), lvl: 11))
            MayhemOverlayView(gameStateManager: mock("Master Yi", [3153, 6676, 3031], kda: (12, 4, 7), lvl: 14))
        }
        .padding(28)
        .background(Color(red: 0.04, green: 0.04, blue: 0.08))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("[preview] render failed"); exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: outPath))
            print("[preview] wrote \(outPath)"); exit(0)
        } catch {
            print("[preview] write failed: \(error)"); exit(1)
        }
    }
}
