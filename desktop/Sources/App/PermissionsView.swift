import SwiftUI

/// In-app permissions panel: shows each macOS privacy permission's status with a one-click
/// grant button (so a rebuild resetting permissions is fixed in two clicks, not a Settings hunt).
struct PermissionsView: View {
    @State private var status: [Bool] = HexPermission.allCases.map { PermissionsManager.isGranted($0) }
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var allRequiredGranted: Bool { status.first == true }   // Accessibility is index 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions Hexlens")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(white: 0.95))
                Text("Active l'Accessibilité pour que le raccourci Tab affiche l'overlay en jeu.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.6))
            }

            ForEach(Array(HexPermission.allCases.enumerated()), id: \.offset) { idx, perm in
                HStack(spacing: 12) {
                    Circle()
                        .fill(status[idx] ? Color(red: 74/255, green: 222/255, blue: 128/255) : Color(red: 248/255, green: 113/255, blue: 113/255))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(perm.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.92))
                        Text(perm.why).font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
                    }
                    Spacer()
                    if status[idx] {
                        Text("Activé").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 74/255, green: 222/255, blue: 128/255))
                    } else {
                        Button("Autoriser") { PermissionsManager.request(perm) }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 200/255, green: 170/255, blue: 110/255))
                            .controlSize(.small)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            }

            HStack {
                Text(allRequiredGranted ? "Prêt — maintiens Tab en jeu." : "Après avoir autorisé, relance Hexlens.")
                    .font(.system(size: 11))
                    .foregroundStyle(allRequiredGranted ? Color(red: 74/255, green: 222/255, blue: 128/255) : Color(white: 0.5))
                Spacer()
                Button("Relancer Hexlens") { PermissionsManager.relaunch() }
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(red: 10/255, green: 10/255, blue: 26/255))
        .onReceive(timer) { _ in
            status = HexPermission.allCases.map { PermissionsManager.isGranted($0) }
        }
    }
}
