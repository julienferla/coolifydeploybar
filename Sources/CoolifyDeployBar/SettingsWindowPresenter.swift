import AppKit
import SwiftUI

/// Héberge les réglages dans une `NSWindow` séparée. Les sheets attachées à une
/// `MenuBarExtra` se ferment souvent au premier clic dans un champ (perte de focus).
enum SettingsWindowPresenter {
    private static var window: NSWindow?
    private static let delegate = WindowDelegate()

    @MainActor
    static func show(settings: AppSettings) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let w = window {
            w.contentView = makeHostingView(settings: settings)
            w.makeKeyAndOrderFront(nil)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Réglages — Coolify Deploy Bar"
        w.contentView = makeHostingView(settings: settings)
        w.isReleasedWhenClosed = false
        w.delegate = delegate
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    @MainActor
    private static func makeHostingView(settings: AppSettings) -> NSView {
        NSHostingView(
            rootView: SettingsView()
                .environmentObject(settings)
                .frame(minWidth: 520, minHeight: 420)
        )
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
