import Foundation
import UserNotifications

/// Notifications système quand un déploiement se termine (succès / échec).
enum DeployNotificationService {
    /// Clé `userInfo` pour l’URL à ouvrir dans le navigateur (Coolify UI).
    static let userInfoURLKey = "coolifyURL"
    static let categoryDeploymentFinished = "COOLIFY_DEPLOY_FINISHED"
    static let actionOpenCoolify = "OPEN_COOLIFY"

    static func registerNotificationCategories() {
        let open = UNNotificationAction(
            identifier: actionOpenCoolify,
            title: "Ouvrir dans Coolify",
            options: [.foreground]
        )
        let cat = UNNotificationCategory(
            identifier: categoryDeploymentFinished,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    static func ensureAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    @MainActor
    static func postCompletionIfNeeded(
        from oldVisual: MenuBarDeploymentVisual,
        to newVisual: MenuBarDeploymentVisual,
        completedItem: DeploymentQueueItem?,
        notifyEnabled: Bool,
        openURL: URL?
    ) async {
        guard notifyEnabled else { return }
        guard oldVisual == .deploying else { return }
        guard newVisual == .success || newVisual == .failure else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = categoryDeploymentFinished

        let appName = completedItem?.application_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleApp = (appName?.isEmpty == false) ? appName! : "Coolify Deploy Bar"

        if newVisual == .success {
            content.title = "Déploiement terminé"
            content.subtitle = titleApp
            content.body = bodyLine(for: completedItem, success: true)
        } else {
            content.title = "Déploiement en échec"
            content.subtitle = titleApp
            content.body = bodyLine(for: completedItem, success: false)
        }

        if let openURL {
            content.userInfo = [userInfoURLKey: openURL.absoluteString]
        }

        let id = "deploy-finished-\(completedItem?.deployment_uuid ?? UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Échec silencieux : l’utilisateur garde l’icône barre de menus.
        }
    }

    private static func bodyLine(for item: DeploymentQueueItem?, success: Bool) -> String {
        guard let item else {
            return success ? "Le build s’est terminé avec succès." : "Le build s’est terminé en erreur."
        }
        var parts: [String] = []
        if let c = item.commit?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            let short = String(c.prefix(7))
            parts.append("Commit \(short)")
        }
        if let msg = item.commit_message?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
            let clipped = msg.count > 120 ? String(msg.prefix(117)) + "…" : msg
            parts.append(clipped)
        }
        if parts.isEmpty {
            parts.append("Statut : \(item.status)")
        }
        return parts.joined(separator: " — ")
    }
}
