import AppKit
import SwiftUI

/// SF Symbol rendu en **palette AppKit** : dans un `MenuBarExtra`, `Image(systemName:)` + `foregroundStyle`
/// est souvent forcé en **template monochrome** ; `NSImage` + `paletteColors` conserve vert / rouge / accent.
private enum MenuBarPaletteSymbol {
    static let systemName = "arrow.triangle.branch"
    static let pointSize: CGFloat = 15

    static func image(colors: [NSColor]) -> NSImage? {
        guard let base = NSImage(systemSymbolName: systemName, accessibilityDescription: "Coolify Deploy Bar") else {
            return nil
        }
        let size = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let palette = NSImage.SymbolConfiguration(paletteColors: colors)
        let config = size.applying(palette)
        guard let configured = base.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false
        return configured
    }

    @ViewBuilder
    static func view(colors: [NSColor]) -> some View {
        if let img = image(colors: colors) {
            Image(nsImage: img)
        } else {
            Image(systemName: systemName)
                .foregroundStyle(Color(nsColor: colors[0]))
        }
    }
}

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
        MenuBarIconView(state: monitor.menuBarVisual, deployingPulse: monitor.menuBarDeployingPulse)
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
    /// Mis à jour ~20×/s par `DeploymentMonitor` pendant `.deploying` pour forcer le redraw du label `MenuBarExtra`.
    let deployingPulse: UInt64

    var body: some View {
        Group {
            switch state {
            case .deploying:
                deployingIcon
            case .idle:
                MenuBarPaletteSymbol.view(colors: [.labelColor])
            case .success:
                MenuBarPaletteSymbol.view(colors: [.systemGreen])
            case .failure:
                MenuBarPaletteSymbol.view(colors: [.systemRed])
            }
        }
        // `MenuBarExtra` met souvent en cache le label : l’identité change à chaque tick en déploiement
        // pour forcer le rendu, et à chaque changement d’état pour idle / succès / échec.
        .id(menuBarLabelIdentity)
        .font(.system(size: 15, weight: .semibold))
        .imageScale(.large)
        .frame(width: 22, height: 18)
    }

    private var menuBarLabelIdentity: String {
        switch state {
        case .deploying:
            return "deploying-\(deployingPulse)"
        case .idle:
            return "idle"
        case .success:
            return "success"
        case .failure:
            return "failure"
        }
    }

    /// `MenuBarExtra` ne rafraîchit souvent pas `TimelineView` / `symbolEffect` ; le remplissage suit
    /// `deployingPulse` (publié depuis le moniteur) pour invalider la vue à chaque tick.
    private var deployingIcon: some View {
        let t = Double(deployingPulse) * 0.22
        // Remplissage bas → haut bien lisible (évite un « pulse » trop subtil).
        let deployFill = CGFloat((sin(t) + 1) / 2) * 0.9 + 0.1
        let accent = NSColor.controlAccentColor
        let pale = accent.withAlphaComponent(0.45)
        return ZStack {
            MenuBarPaletteSymbol.view(colors: [pale])
            MenuBarPaletteSymbol.view(colors: [accent])
                .mask(alignment: .bottom) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(height: max(2, geo.size.height * deployFill))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
        }
        .compositingGroup()
    }
}
