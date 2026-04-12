import SwiftUI

/// Icône de la barre de menus : bleu clignotant en déploiement, vert / rouge selon le dernier résultat.
enum MenuBarDeploymentVisual: Equatable {
    case idle
    case deploying
    case success
    case failure
}

struct MenuBarIconView: View {
    let state: MenuBarDeploymentVisual
    @State private var pulse = false

    var body: some View {
        Image(systemName: "arrow.triangle.branch")
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(foregroundColor)
            .opacity(state == .deploying ? (pulse ? 0.35 : 1.0) : 1.0)
            .animation(
                state == .deploying
                    ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true)
                    : .default,
                value: pulse
            )
            .onAppear {
                pulse = true
            }
            .onChange(of: state) { _, new in
                if new == .deploying {
                    pulse = true
                } else {
                    pulse = false
                }
            }
    }

    private var foregroundColor: Color {
        switch state {
        case .idle: return .primary
        case .deploying: return .blue
        case .success: return .green
        case .failure: return .red
        }
    }
}
