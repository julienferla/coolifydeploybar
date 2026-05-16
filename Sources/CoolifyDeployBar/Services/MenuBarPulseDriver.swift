import Foundation
import SwiftUI

/// Pulse d’animation **isolé** du `DeploymentMonitor` : incrémenter un `@Published` sur le moniteur
/// forçait `objectWillChange` sur tout le menu (popover) ~20×/s et rendait le scroll inutilisable pendant un déploiement.
@MainActor
final class MenuBarPulseDriver: ObservableObject {
    @Published private(set) var value: UInt64 = 0

    func tick() {
        value &+= 1
    }
}
