import AppKit

/// Windows-style vertical maximize: drag a window's top or bottom edge to the menu bar / Dock and it fills
/// the screen height, keeping its x and width. A translucent preview grows to the target while the cursor
/// is at the edge (like macOS' drag-to-fill); releasing applies it, leaving the edge cancels it.
@MainActor
final class EdgeResizeSnap {
    private struct Tracking {
        let window: AXWindow
        let edge: WindowLayout.ResizeEdge
        let startFrame: CGRect
    }

    private var monitor: Any?
    private var downLocation: CGPoint?
    private var tracking: Tracking?
    private var pendingTarget: CGRect?
    private let preview = SnapPreview()

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            [weak self] event in
            MainActor.assumeIsolated { self?.handle(event.type) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    private func handle(_ type: NSEvent.EventType) {
        let location = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown:
            reset()
            downLocation = location
        case .leftMouseDragged:
            if let down = downLocation {
                // Hit-test once per drag, only when it actually becomes a drag.
                downLocation = nil
                tracking = Self.trackingCandidate(at: down)
            }
            if let tracking { update(tracking, cursor: location) }
        case .leftMouseUp:
            if let tracking, let target = pendingTarget {
                // Let the app finish its own live resize first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return }
                    tracking.window.setFrame(WindowLayout.flipped(target, primaryScreenMaxY: primaryMaxY))
                }
            }
            reset()
        default:
            break
        }
    }

    private func update(_ tracking: Tracking, cursor: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }),
              WindowLayout.isAtScreenEdge(cursor, edge: tracking.edge, visibleFrame: screen.visibleFrame) else {
            pendingTarget = nil
            preview.hide()
            return
        }
        guard pendingTarget == nil, let current = Self.cocoaFrame(of: tracking.window) else { return }
        // Only a real top/bottom resize (same width, height changing), not a title-bar move along the top.
        guard abs(current.width - tracking.startFrame.width) <= 2,
              abs(current.height - tracking.startFrame.height) > 2 else { return }
        let target = WindowLayout.verticalFill(current, visibleFrame: screen.visibleFrame)
        pendingTarget = target
        preview.show(from: current, to: target)
    }

    private func reset() {
        downLocation = nil
        tracking = nil
        pendingTarget = nil
        preview.hide()
    }

    /// The resize area straddles the border, so also probe just inside the window.
    private static func trackingCandidate(at point: CGPoint) -> Tracking? {
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return nil }
        for dy: CGFloat in [0, -6, 6] {
            let probe = CGPoint(x: point.x, y: primaryMaxY - (point.y + dy))
            guard let window = AXWindow.at(probe), window.isResizable, let frame = cocoaFrame(of: window),
                  let edge = WindowLayout.resizeEdge(at: point, window: frame) else { continue }
            return Tracking(window: window, edge: edge, startFrame: frame)
        }
        return nil
    }

    private static func cocoaFrame(of window: AXWindow) -> CGRect? {
        guard let frame = window.frame, let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return nil }
        return WindowLayout.flipped(frame, primaryScreenMaxY: primaryMaxY)
    }
}

/// Click-through translucent rounded rectangle that animates from the window to the target frame.
@MainActor
private final class SnapPreview {
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        effect.alphaValue = 0.6
        panel.contentView = effect
        return panel
    }()

    private var isVisible = false

    func show(from start: CGRect, to target: CGRect) {
        isVisible = true
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
    }
}
