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
    private static let defaultSize = NSSize(width: 480, height: 700)
    private static let resizeGrabMargin: CGFloat = 8
    private static let minSize = NSSize(width: 360, height: 400)
    private static let widthKey = "dictionary.panelWidth"
    private static let heightKey = "dictionary.panelHeight"

    private var panel: DictionaryPanel?
    private var webView: WKWebView?
    private var resignObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

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
        let size = Self.savedSize()
        let webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: WKWebViewConfiguration())
        webView.uiDelegate = self
        webView.load(URLRequest(url: currentSite().url))

        let panel = DictionaryPanel(
            contentRect: NSRect(origin: Self.origin(for: size), size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.minSize = Self.minSize
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
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                // Grabbing the panel's edge to resize it also resigns key; that is not an outside click.
                if let panel, NSEvent.pressedMouseButtons != 0,
                   panel.frame.insetBy(dx: -Self.resizeGrabMargin, dy: -Self.resizeGrabMargin).contains(NSEvent.mouseLocation) {
                    return
                }
                self?.close()
            }
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel else { return }
                UserDefaults.standard.set(panel.frame.size.width, forKey: Self.widthKey)
                UserDefaults.standard.set(panel.frame.size.height, forKey: Self.heightKey)
                // The edge grab took key away; take it back so Esc and the outside-click close keep working.
                panel.makeKey()
            }
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
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
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

    /// The size the user last dragged the panel to, or the default; never larger than the screen's usable area.
    private static func savedSize() -> NSSize {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: widthKey)
        let height = defaults.double(forKey: heightKey)
        var size = width > 0 && height > 0 ? NSSize(width: width, height: height) : defaultSize
        if let area = NSScreen.main?.visibleFrame {
            size.width = min(size.width, area.width)
            size.height = min(size.height, area.height - 8)
        }
        return NSSize(width: max(size.width, minSize.width), height: max(size.height, minSize.height))
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
