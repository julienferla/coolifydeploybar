import Combine
import Foundation

final class AppSettings: ObservableObject {
    @Published var baseURL: String { didSet { save() } }
    @Published var apiToken: String { didSet { save() } }
    /// UUID d'application Coolify pour l'historique dans le menu (optionnel mais recommandé).
    @Published var applicationUUID: String { didSet { save() } }
    @Published var pollIntervalSeconds: Double { didSet { save() } }
    /// Notification macOS quand un déploiement passe de « en cours » à terminé (succès ou échec).
    @Published var notifyOnDeploymentComplete: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let baseURL = "cdb.baseURL"
        static let apiToken = "cdb.apiToken"
        static let applicationUUID = "cdb.applicationUUID"
        static let poll = "cdb.pollIntervalSeconds"
        static let notifyOnDeployDone = "cdb.notifyOnDeploymentComplete"
    }

    init() {
        baseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        apiToken = defaults.string(forKey: Keys.apiToken) ?? ""
        applicationUUID = defaults.string(forKey: Keys.applicationUUID) ?? ""
        let stored = defaults.object(forKey: Keys.poll) as? Double
        pollIntervalSeconds = stored ?? 30
        if defaults.object(forKey: Keys.notifyOnDeployDone) == nil {
            notifyOnDeploymentComplete = true
        } else {
            notifyOnDeploymentComplete = defaults.bool(forKey: Keys.notifyOnDeployDone)
        }
    }

    private func save() {
        defaults.set(baseURL, forKey: Keys.baseURL)
        defaults.set(apiToken, forKey: Keys.apiToken)
        defaults.set(applicationUUID, forKey: Keys.applicationUUID)
        defaults.set(pollIntervalSeconds, forKey: Keys.poll)
        defaults.set(notifyOnDeploymentComplete, forKey: Keys.notifyOnDeployDone)
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
