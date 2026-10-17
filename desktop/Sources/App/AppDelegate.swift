import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayWindowController?
    private var onboardingPopover: NSPopover?
    private var permissionsWindow: NSWindow?
    private let gameStateManager = GameStateManager()

    private func debugLog(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        if let data = line.data(using: .utf8) {
            let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("hexlens-debug.log")
            if FileManager.default.fileExists(atPath: logFile.path) {
                let handle = try? FileHandle(forWritingTo: logFile)
                handle?.seekToEndOfFile()
                handle?.write(data)
                handle?.closeFile()
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("applicationDidFinishLaunching")

        // Demo/preview mode: show the real overlay with mock game state, no LoL required.
        if CommandLine.arguments.contains("--demo") {
            NSApp.setActivationPolicy(.regular)
            setupMenuBar()
            setupOverlay()
            // Optional scene: `--demo classic` (Summoner's Rift) or `--demo yi` (Mayhem, on-hit build).
            let args = CommandLine.arguments
            let scene = args.firstIndex(of: "--demo").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "mayhem"
            gameStateManager.dataDragonVersion = "16.12.1"
            switch scene {
            case "classic": loadClassicDemo()
            case "yi":
                gameStateManager.gameMode = "KIWI"
                gameStateManager.activeChampionName = "Master Yi"
                gameStateManager.activeItemIDs = [3153, 6676, 3031]   // BotRK, Collector, Infinity Edge (on-hit)
                gameStateManager.playerLevel = 14
                gameStateManager.kda = (12, 4, 7)
            default:
                gameStateManager.gameMode = "KIWI"
                gameStateManager.activeChampionName = "Nidalee"
                gameStateManager.activeItemIDs = [3089, 3115, 6653]   // Rabadon's, Nashor's, Liandry's (AP build)
                gameStateManager.playerLevel = 11
                gameStateManager.kda = (8, 2, 6)
                gameStateManager.currentCS = 24
                gameStateManager.csPerMin = 2.1
                gameStateManager.goldPerMin = 412
                gameStateManager.killParticipation = 72
                gameStateManager.visionPerMin = 0.8
            }
            let svc = AugmentDataService.shared
            FileHandle.standardError.write("[demo] loaded augments=\(svc.catalog?.augments.count ?? -1) champions=\(svc.champions?.champions.count ?? -1) items=\(svc.items?.items.count ?? -1)\n".data(using: .utf8)!)
            overlayController?.showForDemo()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Background app: no Dock icon, no Cmd-Tab entry
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        debugLog("menu bar set up")
        setupOverlay()
        debugLog("overlay set up")
        setupNotifications()
        debugLog("notifications set up")
        showOnboardingIfNeeded()
        debugLog("onboarding checked")

        gameStateManager.start()
        debugLog("gameStateManager started")

        // First thing the user sees if the required permission is missing (e.g. after a rebuild
        // reset it): the in-app Permissions panel with one-click grant buttons.
        if !PermissionsManager.isGranted(.accessibility) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.openPermissions() }
        }
    }

    /// Mock Summoner's Rift mid-game state for `--demo classic` (screenshots, no LoL required).
    private func loadClassicDemo() {
        let g = gameStateManager
        g.gameMode = "CLASSIC"
        g.activeChampionName = "Ahri"
        g.playerLevel = 13
        g.kda = (7, 2, 9)
        g.currentCS = 186
        g.csPerMin = 8.3
        g.goldPerMin = 468
        g.killParticipation = 64
        g.visionPerMin = 0.9
        g.allyTeamGold = 38_400
        g.enemyTeamGold = 35_150
        g.laneMatchups = [
            LaneMatchup(id: "TOP", position: "TOP", allyChampion: "Garen", enemyChampion: "Darius", allyGold: 7_450, enemyGold: 7_980),
            LaneMatchup(id: "JUNGLE", position: "JUNGLE", allyChampion: "LeeSin", enemyChampion: "Viego", allyGold: 7_200, enemyGold: 6_550),
            LaneMatchup(id: "MIDDLE", position: "MIDDLE", allyChampion: "Ahri", enemyChampion: "Syndra", allyGold: 9_100, enemyGold: 7_600),
            LaneMatchup(id: "BOTTOM", position: "BOTTOM", allyChampion: "Jinx", enemyChampion: "Caitlyn", allyGold: 9_350, enemyGold: 8_900),
            LaneMatchup(id: "UTILITY", position: "UTILITY", allyChampion: "Thresh", enemyChampion: "Lulu", allyGold: 5_300, enemyGold: 4_120),
        ]
        func spell(_ id: String, cd: TimeInterval, remaining: TimeInterval? = nil) -> SpellCooldownState {
            SpellCooldownState(spellName: id, rawDisplayName: "GeneratedTip_SummonerSpell_\(id)_DisplayName",
                               cooldownEnd: remaining.map { Date().addingTimeInterval($0) }, baseCooldown: cd)
        }
        func ult(_ remaining: TimeInterval? = nil) -> SpellCooldownState {
            SpellCooldownState(spellName: "R", rawDisplayName: nil,
                               cooldownEnd: remaining.map { Date().addingTimeInterval($0) }, baseCooldown: 100)
        }
        g.enemySpells = [
            EnemySpellState(id: "e1", championName: "Darius", spell1: spell("SummonerFlash", cd: 300),
                            spell2: spell("SummonerTeleport", cd: 360, remaining: 214), ult: ult(), level: 13),
            EnemySpellState(id: "e2", championName: "Viego", spell1: spell("SummonerFlash", cd: 300, remaining: 167),
                            spell2: spell("SummonerSmite", cd: 15), ult: ult(42), level: 12),
            EnemySpellState(id: "e3", championName: "Syndra", spell1: spell("SummonerFlash", cd: 300),
                            spell2: spell("SummonerDot", cd: 180), ult: ult(), level: 11),
            EnemySpellState(id: "e4", championName: "Caitlyn", spell1: spell("SummonerFlash", cd: 300, remaining: 241),
                            spell2: spell("SummonerHeal", cd: 240), ult: ult(), level: 12),
            EnemySpellState(id: "e5", championName: "Lulu", spell1: spell("SummonerFlash", cd: 300),
                            spell2: spell("SummonerExhaust", cd: 210, remaining: 88), ult: ult(61), level: 10),
        ]
    }

    @objc private func openPermissions() {
        if permissionsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Hexlens — Permissions"
            w.contentViewController = NSHostingController(rootView: PermissionsView())
            w.isReleasedWhenClosed = false
            w.center()
            permissionsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        permissionsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 280)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: OnboardingView(onDismiss: { [weak self] in
                self?.onboardingPopover?.close()
                self?.onboardingPopover = nil
            })
        )
        self.onboardingPopover = popover

        // Show from menu bar button after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let button = self?.statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "League Overlay")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Waiting for LoL...", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Permissions…", action: #selector(openPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toggle Overlay Position Mode", action: #selector(toggleOverlayMode), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Copy Debug Info", action: #selector(copyDebugInfo), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Observe state changes to update menu bar text
        gameStateManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateMenuBarForState(state)
                // Arm the overlay as soon as a game is detected, regardless of when the app
                // was launched (fixes "launched mid-game → Tab does nothing").
                if state == .inGame { self?.overlayController?.showOverlay() }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func updateMenuBarForState(_ state: GameLifecycleState) {
        let statusText: String
        switch state {
        case .idle: statusText = "Waiting for LoL..."
        case .lobby: statusText = "● In Lobby"
        case .champSelect: statusText = "● Champ Select"
        case .loading: statusText = "Loading..."
        case .inGame: statusText = "● In Game"
        case .postGame: statusText = "Game Over"
        }
        if let menu = statusItem.menu, let firstItem = menu.items.first {
            firstItem.title = statusText
        }
    }

    @objc private func toggleOverlayMode() {
        overlayController?.toggleInteractiveMode()
    }

    @objc private func copyDebugInfo() {
        let info = """
        Mac League Overlay - Debug Info
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        State: \(gameStateManager.state.rawValue)
        LoL detected: \(gameStateManager.state != .idle)
        Overlay opacity: \(UserDefaults.standard.double(forKey: "overlayOpacity"))
        LoL path: \(UserDefaults.standard.string(forKey: "lolInstallPath") ?? "default")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }

    private func setupOverlay() {
        overlayController = OverlayWindowController(gameStateManager: gameStateManager)
    }

    private func setupNotifications() {
        // Hide overlay when LoL loses focus
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Respond immediately to focus loss
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let isLoL = app.bundleIdentifier == "com.riotgames.LeagueofLegends.GameClient"
            || app.localizedName?.contains("League") == true
        if isLoL && gameStateManager.state == .inGame {
            overlayController?.showOverlay()
        }
    }

    @objc private func appDidResignActive(_ notification: Notification) {
        // Don't hide overlay during interactive mode (drag-to-reposition)
        guard overlayController?.isInInteractiveMode != true else { return }
        overlayController?.hideOverlay()
    }

    func updateMenuBarStatus(_ status: String) {
        if let menu = statusItem.menu, let firstItem = menu.items.first {
            firstItem.title = status
        }
    }
}
