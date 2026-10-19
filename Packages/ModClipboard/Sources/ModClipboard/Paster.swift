import AppKit

/// Pastes the current clipboard into another app by re-activating it and posting ⌘V.
/// Posting keyboard events to other apps requires the Accessibility permission.
@MainActor
enum Paster {
    /// ANSI "V". ⌘ shortcuts resolve by physical key on QWERTY-based layouts (incl. Korean 2-set).
    private static let vKeyCode: CGKeyCode = 9

    static func paste(into app: NSRunningApplication) {
        app.activate()
        Task { @MainActor in
            // Wait (≤ 0.5 s) for the target to become frontmost, otherwise ⌘V lands in the wrong app.
            for _ in 0..<25 where NSWorkspace.shared.frontmostApplication != app {
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard NSWorkspace.shared.frontmostApplication == app else { return }
            try? await Task.sleep(for: .milliseconds(50))
            postCommandV()
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
