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
            MenuBarLabelView(settings: settings, monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
