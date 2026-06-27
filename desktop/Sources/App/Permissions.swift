import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid

/// The macOS privacy permissions Hexlens needs. Accessibility is REQUIRED for the
/// hold-Tab global hotkey; Screen Recording is for the (upcoming) live augment reader.
enum HexPermission: CaseIterable {
    case accessibility      // global Tab hotkey (NSEvent global monitor)
    case inputMonitoring    // some macOS versions also gate global key events here
    case screenRecording    // live augment-screen reader (coming)

    var title: String {
        switch self {
        case .accessibility: return "Accessibilité"
        case .inputMonitoring: return "Surveillance de la saisie"
        case .screenRecording: return "Enregistrement de l'écran"
        }
    }
    var why: String {
        switch self {
        case .accessibility: return "Requis — détecter la touche Tab pour afficher l'overlay"
        case .inputMonitoring: return "Recommandé — secours pour le raccourci Tab"
        case .screenRecording: return "Pour le lecteur d'augments en direct (à venir)"
        }
    }
    var settingsAnchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .inputMonitoring: return "Privacy_ListenEvent"
        case .screenRecording: return "Privacy_ScreenCapture"
        }
    }
}

enum PermissionsManager {
    static func isGranted(_ p: HexPermission) -> Bool {
        switch p {
        case .accessibility: return AXIsProcessTrusted()
        case .inputMonitoring: return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        }
    }

    /// Trigger the system permission prompt (when possible) AND open the relevant settings pane.
    static func request(_ p: HexPermission) {
        switch p {
        case .accessibility:
            let opt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([opt: true] as CFDictionary)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        openSettings(p)
    }

    static func openSettings(_ p: HexPermission) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(p.settingsAnchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Relaunch the app (needed for newly-granted Accessibility to take effect on the global monitor).
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
