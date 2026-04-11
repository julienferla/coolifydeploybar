import SwiftUI

@main
struct CoolifyDeployBarApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var monitor = DeploymentMonitor()

    var body: some Scene {
        MenuBarExtra("Coolify", systemImage: "arrow.triangle.branch") {
            DeploymentMenuView()
                .environmentObject(settings)
                .environmentObject(monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
