import AppKit
import SwiftUI

/// Icône de la barre de menus : bleu animé en déploiement, vert / rouge selon le dernier résultat.
enum MenuBarDeploymentVisual: Equatable {
    case idle
    case deploying
    case success
    case failure
}

/// Label toujours monté : observe le moniteur et lance le polling dès que la config est prête
/// (sans attendre l’ouverture du popover — sinon l’icône ne suivait jamais les déploiements).
struct MenuBarLabelView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: DeploymentMonitor

    private var connectionFingerprint: String {
        settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            + "|" + settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        MenuBarIconView(state: monitor.menuBarVisual)
            .accessibilityLabel("Coolify Deploy Bar")
            .task(id: connectionFingerprint) {
                guard settings.isConfigured else {
                    monitor.stopPolling()
                    return
                }
                monitor.startPolling(settings: settings)
                if settings.notifyOnDeploymentComplete {
                    await DeployNotificationService.ensureAuthorization()
                }
                await monitor.refresh(settings: settings)
            }
    }
}

struct MenuBarIconView: View {
    let state: MenuBarDeploymentVisual
    /// 0…1 : remplissage du glyphe du bas vers le haut (visible même en rendu template de la barre de menus).
    @State private var deployFill: CGFloat = 0

    private static let deployFillAnimation = Animation
        .easeInOut(duration: 1.1)
        .repeatForever(autoreverses: true)

    var body: some View {
        Group {
            switch state {
            case .deploying:
                deployingIcon
            case .idle:
                Image(systemName: "arrow.triangle.branch")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.primary)
            case .success:
                Image(systemName: "arrow.triangle.branch")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color(nsColor: .systemGreen))
            case .failure:
                Image(systemName: "arrow.triangle.branch")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color(nsColor: .systemRed))
            }
        }
        .imageScale(.medium)
        .onAppear { syncDeployAnimationIfNeeded() }
        .onChange(of: state) { _, _ in syncDeployAnimationIfNeeded() }
    }

    /// Double calque + masque : la barre de menus applique souvent un rendu template aux SF Symbols,
    /// ce qui aplatit les LinearGradient ; ici le « remplissage » reste lisible (contraste haut/bas).
    private var deployingIcon: some View {
        ZStack {
            Image(systemName: "arrow.triangle.branch")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.blue.opacity(0.28))
            Image(systemName: "arrow.triangle.branch")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.blue)
                .mask(alignment: .bottom) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(height: max(1, geo.size.height * deployFill))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
        }
        // Cadre fixe : évite que le GeometryReader du masque n’étire l’icône dans la barre de menus.
        .frame(width: 18, height: 14)
    }

    private func syncDeployAnimationIfNeeded() {
        if state == .deploying {
            deployFill = 0.12
            withAnimation(Self.deployFillAnimation) {
                deployFill = 1
            }
        } else {
            withAnimation(.default) {
                deployFill = 0
            }
        }
    }
}
