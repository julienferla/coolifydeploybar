import SwiftUI

@main
struct CoolifyDeployBarApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var monitor = DeploymentMonitor()

    var body: some Scene {
        MenuBarExtra {
            DeploymentMenuView()
                .environmentObject(settings)
                .environmentObject(monitor)
        } label: {
            MenuBarIconView(state: monitor.menuBarVisual)
                .accessibilityLabel("Coolify Deploy Bar")
        }
        .menuBarExtraStyle(.window)
    }
}
