import Combine
import Foundation

final class AppSettings: ObservableObject {
    @Published var baseURL: String { didSet { saveDefaults() } }
    /// Token API Coolify : stocké dans le Keychain (jamais en UserDefaults).
    @Published var apiToken: String { didSet { KeychainTokenStore.write(apiToken) } }
    /// UUID d'application Coolify pour l'historique dans le menu (optionnel mais recommandé).
    @Published var applicationUUID: String { didSet { saveDefaults() } }
    @Published var pollIntervalSeconds: Double { didSet { saveDefaults() } }
    /// Notification macOS quand un déploiement passe de « en cours » à terminé (succès ou échec).
    @Published var notifyOnDeploymentComplete: Bool { didSet { saveDefaults() } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let baseURL = "cdb.baseURL"
        /// Ancienne clé : token plaintext en UserDefaults (versions ≤ 1.0.3). Migré au démarrage.
        static let legacyAPIToken = "cdb.apiToken"
        static let applicationUUID = "cdb.applicationUUID"
        static let poll = "cdb.pollIntervalSeconds"
        static let notifyOnDeployDone = "cdb.notifyOnDeploymentComplete"
    }

    init() {
        baseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        applicationUUID = defaults.string(forKey: Keys.applicationUUID) ?? ""
        let stored = defaults.object(forKey: Keys.poll) as? Double
        pollIntervalSeconds = stored ?? 30
        if defaults.object(forKey: Keys.notifyOnDeployDone) == nil {
            notifyOnDeploymentComplete = true
        } else {
            notifyOnDeploymentComplete = defaults.bool(forKey: Keys.notifyOnDeployDone)
        }

        // Migration plaintext UserDefaults → Keychain. Sans cela, un token existant
        // reste lisible dans ~/Library/Preferences/com.julienferla.CoolifyDeployBar.plist
        // par n'importe quel process tournant sous l'utilisateur.
        let keychainToken = KeychainTokenStore.read()
        let legacyToken = (defaults.string(forKey: Keys.legacyAPIToken) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !keychainToken.isEmpty {
            apiToken = keychainToken
            if !legacyToken.isEmpty {
                defaults.removeObject(forKey: Keys.legacyAPIToken)
            }
        } else if !legacyToken.isEmpty {
            apiToken = legacyToken
            KeychainTokenStore.write(legacyToken)
            defaults.removeObject(forKey: Keys.legacyAPIToken)
        } else {
            apiToken = ""
        }
    }

    private func saveDefaults() {
        defaults.set(baseURL, forKey: Keys.baseURL)
        defaults.set(applicationUUID, forKey: Keys.applicationUUID)
        defaults.set(pollIntervalSeconds, forKey: Keys.poll)
        defaults.set(notifyOnDeploymentComplete, forKey: Keys.notifyOnDeployDone)
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
