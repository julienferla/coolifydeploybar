import AppKit
import UserNotifications

/// Délégué app : catégories de notifications + ouverture Coolify au clic.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        DeployNotificationService.registerNotificationCategories()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Self.openCoolifyURLIfPresent(response.notification.request.content.userInfo)
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    static func openCoolifyURLIfPresent(_ userInfo: [AnyHashable: Any]) {
        guard let s = userInfo[DeployNotificationService.userInfoURLKey] as? String,
              let u = URL(string: s)
        else { return }
        NSWorkspace.shared.open(u)
    }
}
