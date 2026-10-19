import AppKit
import SwiftUI
import TUCore

@MainActor
final class SettingsWindowController {
    private let registry: ModuleRegistry
    private let permissions: PermissionCenter
    private var window: NSWindow?

    init(registry: ModuleRegistry, permissions: PermissionCenter) {
        self.registry = registry
        self.permissions = permissions
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(registry: registry, permissions: permissions))
            let window = NSWindow(contentViewController: hosting)
            window.title = "T-Utilities 설정"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 720, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
