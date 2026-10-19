import AppKit
import TUCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let popoverControl = PopoverControl()
    private lazy var registry = ModuleRegistry(modules: AppModules.all, store: ModuleStateStore(), popover: popoverControl)
    private let permissions = PermissionCenter()
    private let updater = Updater()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        let settingsWindow = SettingsWindowController(registry: registry, permissions: permissions, updater: updater)
        self.settingsWindow = settingsWindow
        statusItem = StatusItemController(registry: registry, updater: updater, popoverControl: popoverControl) {
            settingsWindow.show()
        }

        Task {
            await registry.startEnabledModules()
        }
        updater.startSchedule()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Modules may need to restore system state (pointer acceleration, sleep settings) before exit.
        Task {
            await registry.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Accessory apps have no visible menu bar, but text fields still need Edit menu key equivalents (⌘C/⌘V…).
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
