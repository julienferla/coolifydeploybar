import Combine
import Foundation

final class AppSettings: ObservableObject {
    @Published var baseURL: String { didSet { save() } }
    @Published var apiToken: String { didSet { save() } }
    /// UUID d'application Coolify pour l'historique dans le menu (optionnel mais recommandé).
    @Published var applicationUUID: String { didSet { save() } }
    @Published var pollIntervalSeconds: Double { didSet { save() } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let baseURL = "cdb.baseURL"
        static let apiToken = "cdb.apiToken"
        static let applicationUUID = "cdb.applicationUUID"
        static let poll = "cdb.pollIntervalSeconds"
    }

    init() {
        baseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        apiToken = defaults.string(forKey: Keys.apiToken) ?? ""
        applicationUUID = defaults.string(forKey: Keys.applicationUUID) ?? ""
        let stored = defaults.object(forKey: Keys.poll) as? Double
        pollIntervalSeconds = stored ?? 30
    }

    private func save() {
        defaults.set(baseURL, forKey: Keys.baseURL)
        defaults.set(apiToken, forKey: Keys.apiToken)
        defaults.set(applicationUUID, forKey: Keys.applicationUUID)
        defaults.set(pollIntervalSeconds, forKey: Keys.poll)
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
