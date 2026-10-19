import AppKit
import SwiftUI
import TUCore

/// The single menu bar item: main icon (overridable by a module, e.g. Awake) + accessory text (e.g. Clock).
/// Left click toggles the popover, right click shows the quick menu.
@MainActor
final class StatusItemController: NSObject {
    private static let defaultSymbol = "square.grid.2x2"

    private let registry: ModuleRegistry
    private let openSettings: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(registry: ModuleRegistry, openSettings: @escaping () -> Void) {
        self.registry = registry
        self.openSettings = openSettings
        super.init()

        popover.behavior = .transient
        popover.animates = false
        let hosting = NSHostingController(rootView: PopoverView(registry: registry) { [weak self] in
            self?.popover.performClose(nil)
            openSettings()
        })
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        observeAppearance()
    }

    private func observeAppearance() {
        withObservationTracking {
            updateAppearance()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAppearance() }
        }
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        let modules = registry.activeModules
        let symbol = modules.lazy.compactMap(\.statusItemSymbol).first ?? Self.defaultSymbol
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "T-Utilities")
        image?.isTemplate = true
        button.image = image

        let text = modules.compactMap(\.statusItemText).joined(separator: "  ")
        button.title = text.isEmpty ? "" : " \(text)"
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "설정…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "T-Utilities 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Attach temporarily so the left click keeps opening the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenSettings() {
        openSettings()
    }
}
