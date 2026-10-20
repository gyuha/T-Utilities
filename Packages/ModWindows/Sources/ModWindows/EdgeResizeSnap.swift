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
        /// The window's screen when the drag started; the edge test stays relative to it.
        let screen: WindowLayout.Screen
    }

    /// A window we filled, so moving it restores its previous size like macOS' tiling does.
    private struct Filled {
        let window: AXUIElement
        let originalSize: CGSize
        let filledFrame: CGRect
    }

    private var monitor: Any?
    private var filled: [Filled] = []
    private var restoreCandidate: (entry: Filled, window: AXWindow)?
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
                if tracking == nil { restoreCandidate = filledWindow(at: down) }
            }
            if let tracking {
                update(tracking, cursor: location)
            } else if let restoreCandidate {
                restoreIfMoved(restoreCandidate, cursor: location)
            }
        case .leftMouseUp:
            if let tracking, let target = pendingTarget {
                // Let the app finish its own live resize first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return }
                    tracking.window.setFrame(WindowLayout.flipped(target, primaryScreenMaxY: primaryMaxY))
                    guard let self, let placed = Self.cocoaFrame(of: tracking.window) else { return }
                    filled.removeAll { CFEqual($0.window, tracking.window.element) }
                    filled.append(Filled(window: tracking.window.element, originalSize: tracking.startFrame.size, filledFrame: placed))
                    filled = Array(filled.suffix(20))
                }
            }
            reset()
        default:
            break
        }
    }

    private func update(_ tracking: Tracking, cursor: CGPoint) {
        guard WindowLayout.isAtScreenEdge(cursor, edge: tracking.edge, screen: tracking.screen) else {
            pendingTarget = nil
            preview.hide()
            return
        }
        guard pendingTarget == nil, let current = Self.cocoaFrame(of: tracking.window) else { return }
        // A top/bottom resize never changes x or width; a move usually does. The height may be unchanged
        // (window already at the edge, or dragged away and back), so it isn't required to change.
        guard abs(current.width - tracking.startFrame.width) <= 2,
              abs(current.minX - tracking.startFrame.minX) <= 2 else { return }
        let target = WindowLayout.verticalFill(current, visibleFrame: tracking.screen.visibleFrame)
        pendingTarget = target
        preview.show(from: current, to: target)
    }

    /// A filled window being dragged by its title bar: sideways it stays filled; once it moves up or down,
    /// give back its previous size, keeping the cursor at the same relative spot across the title bar.
    private func restoreIfMoved(_ candidate: (entry: Filled, window: AXWindow), cursor: CGPoint) {
        guard let current = Self.cocoaFrame(of: candidate.window) else { return }
        guard abs(current.width - candidate.entry.filledFrame.width) <= 2,
              abs(current.height - candidate.entry.filledFrame.height) <= 2 else {
            // Resized by other means since: forget it.
            restoreCandidate = nil
            filled.removeAll { CFEqual($0.window, candidate.entry.window) }
            return
        }
        guard WindowLayout.movedVertically(current, filled: candidate.entry.filledFrame),
              let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return }
        restoreCandidate = nil
        filled.removeAll { CFEqual($0.window, candidate.entry.window) }
        let restored = WindowLayout.restoredOnDrag(current, originalSize: candidate.entry.originalSize, cursorX: cursor.x)
        // AX origin is top-left, so setting the size keeps the title bar under the cursor; then fix x.
        candidate.window.set(size: restored.size)
        candidate.window.set(position: WindowLayout.flipped(restored, primaryScreenMaxY: primaryMaxY).origin)
    }

    private func filledWindow(at point: CGPoint) -> (entry: Filled, window: AXWindow)? {
        guard !filled.isEmpty, let primaryMaxY = NSScreen.screens.first?.frame.maxY,
              let window = AXWindow.at(CGPoint(x: point.x, y: primaryMaxY - point.y)),
              let entry = filled.first(where: { CFEqual($0.window, window.element) }),
              let frame = Self.cocoaFrame(of: window), WindowLayout.isStillFilled(frame, filled: entry.filledFrame) else { return nil }
        return (entry, window)
    }

    private func reset() {
        downLocation = nil
        tracking = nil
        restoreCandidate = nil
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
            let screens = NSScreen.screens.map { WindowLayout.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
            guard let screen = WindowLayout.screenContaining(frame, in: screens) else { return nil }
            return Tracking(window: window, edge: edge, startFrame: frame, screen: screen)
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
