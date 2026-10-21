import AppKit
import WebKit

/// Borderless floating panel that can take keyboard focus and handles ESC / ⌘1 / ⌘2 itself,
/// because the web view would otherwise swallow them.
final class DictionaryPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onSelectSite: ((DictionarySite) -> Void)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53, !isComposingText {
                onEscape?()
                return
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               let key = event.charactersIgnoringModifiers, let site = DictionarySite(shortcutKey: key) {
                onSelectSite?(site)
                return
            }
        }
        super.sendEvent(event)
    }

    /// ESC while composing Korean should cancel the composition, not close the panel.
    private var isComposingText: Bool {
        (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }
}

/// Owns the panel and its web view. Both exist only while the panel is shown, so the WebKit
/// content processes go away as soon as it closes.
@MainActor
final class DictionaryPanelController: NSObject, WKUIDelegate {
    private static let size = NSSize(width: 405, height: 500)

    private var panel: DictionaryPanel?
    private var webView: WKWebView?
    private var resignObserver: NSObjectProtocol?

    private let currentSite: () -> DictionarySite
    private let selectSite: (DictionarySite) -> Void

    init(currentSite: @escaping () -> DictionarySite, selectSite: @escaping (DictionarySite) -> Void) {
        self.currentSite = currentSite
        self.selectSite = selectSite
    }

    var isShown: Bool { panel != nil }

    func toggle() {
        isShown ? close() : show()
    }

    func show() {
        guard panel == nil else { return }
        let webView = WKWebView(frame: NSRect(origin: .zero, size: Self.size), configuration: WKWebViewConfiguration())
        webView.uiDelegate = self
        webView.load(URLRequest(url: currentSite().url))

        let panel = DictionaryPanel(
            contentRect: NSRect(origin: Self.origin(for: Self.size), size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.onEscape = { [weak self] in self?.close() }
        panel.onSelectSite = { [weak self] site in self?.switchTo(site) }

        webView.autoresizingMask = [.width, .height]
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 12
        webView.layer?.masksToBounds = true
        panel.contentView = webView

        // Clicking outside (focus moves elsewhere) closes the panel, like allkdic.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }

        self.panel = panel
        self.webView = webView
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
    }

    func close() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        webView?.stopLoading()
        webView?.uiDelegate = nil
        panel?.onEscape = nil
        panel?.onSelectSite = nil
        panel?.contentView = nil
        panel?.orderOut(nil)
        panel?.close()
        // Dropping the last references deallocates the WKWebView, which ends its web content process.
        webView = nil
        panel = nil
    }

    private func switchTo(_ site: DictionarySite) {
        selectSite(site)
        webView?.load(URLRequest(url: site.url))
    }

    /// Horizontally centered on the screen under the mouse, just below the menu bar.
    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        return NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 8)
    }

    // MARK: - WKUIDelegate

    /// target=_blank links open in the default browser instead of a second web view.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            close()
        }
        return nil
    }
}
