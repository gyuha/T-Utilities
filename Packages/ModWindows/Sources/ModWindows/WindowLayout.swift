import CoreGraphics

/// Pure geometry for the supported actions, in Cocoa screen coordinates (origin bottom-left of the
/// primary display). Logic follows Rectangle's ScreenDetection / MaximizeCalculation /
/// NextPrevDisplayCalculation with their default settings.
enum WindowLayout {
    struct Screen: Equatable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// AX frames come back rounded; a couple of points of slack still means "unchanged".
    static func isSameFrame(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    // MARK: Edge-resize snap (top/bottom edge dragged to the screen edge → full visible height)

    enum ResizeEdge: Sendable { case top, bottom }

    /// Which horizontal edge a drag starting at `point` grabs, if any. macOS' resize area straddles the border.
    static func resizeEdge(at point: CGPoint, window: CGRect, band: CGFloat = 6) -> ResizeEdge? {
        guard point.x >= window.minX - band, point.x <= window.maxX + band else { return nil }
        if abs(point.y - window.maxY) <= band { return .top }
        if abs(point.y - window.minY) <= band { return .bottom }
        return nil
    }

    /// Cursor has reached the menu bar / Dock side of the screen for the edge being dragged.
    static func isAtScreenEdge(_ point: CGPoint, edge: ResizeEdge, visibleFrame: CGRect, threshold: CGFloat = 2) -> Bool {
        switch edge {
        case .top: point.y >= visibleFrame.maxY - threshold
        case .bottom: point.y <= visibleFrame.minY + threshold
        }
    }

    /// Previous size for a filled window that started moving: top edge stays (title bar under the cursor) and
    /// the cursor keeps its relative horizontal position, as macOS does when dragging a tiled window away.
    static func restoredOnDrag(_ window: CGRect, originalSize: CGSize, cursorX: CGFloat) -> CGRect {
        let ratio = window.width > 0 ? min(1, max(0, (cursorX - window.minX) / window.width)) : 0.5
        return CGRect(
            x: cursorX - ratio * originalSize.width, y: window.maxY - originalSize.height,
            width: originalSize.width, height: originalSize.height
        )
    }

    /// Same x and width, full visible height.
    static func verticalFill(_ window: CGRect, visibleFrame: CGRect) -> CGRect {
        CGRect(x: window.minX, y: visibleFrame.minY, width: window.width, height: visibleFrame.height)
    }

    enum Action: Sendable {
        case maximize, nextDisplay, previousDisplay
    }

    /// Target frame for `window`, or nil when the action does not apply (e.g. single display).
    static func target(for action: Action, window: CGRect, screens: [Screen]) -> CGRect? {
        let ordered = order(screens)
        guard let current = screenContaining(window, in: ordered) else { return nil }

        switch action {
        case .maximize:
            return current.visibleFrame
        case .nextDisplay, .previousDisplay:
            guard ordered.count > 1, let index = ordered.firstIndex(of: current) else { return nil }
            let step = action == .nextDisplay ? 1 : ordered.count - 1
            let destination = ordered[(index + step) % ordered.count]
            let transferred = DisplayTransfer.transferredRect(
                window: window, source: current.visibleFrame, destination: destination.visibleFrame
            )
            // A maximized window stays maximized on the next display.
            return transferred.sharedEdges == .all ? destination.visibleFrame : transferred.rect
        }
    }

    /// Rectangle's default ordering (`yThenMinX`): top row first, then left to right.
    static func order(_ screens: [Screen]) -> [Screen] {
        screens.sorted { first, second in
            if second.frame.maxY <= first.frame.minY { return true }
            if first.frame.maxY <= second.frame.minY { return false }
            return first.frame.minX < second.frame.minX
        }
    }

    /// The screen that fully contains the window, else the one with the largest share of it.
    static func screenContaining(_ window: CGRect, in screens: [Screen]) -> Screen? {
        if let containing = screens.first(where: { $0.frame.contains(window) }) {
            return containing
        }
        return screens.max { overlap(window, $0.frame) < overlap(window, $1.frame) } ?? screens.first
    }

    private static func overlap(_ window: CGRect, _ frame: CGRect) -> CGFloat {
        let intersection = window.intersection(frame)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    /// Keeps a window that refused the requested size inside the visible frame (Rectangle's BestEffortWindowMover).
    static func constrained(_ window: CGRect, to bounds: CGRect) -> CGRect {
        var result = window
        if result.minX < bounds.minX {
            result.origin.x = bounds.minX
        } else if result.maxX > bounds.maxX {
            result.origin.x = max(bounds.minX, bounds.maxX - result.width)
        }
        if result.minY < bounds.minY {
            result.origin.y = bounds.minY
        } else if result.maxY > bounds.maxY {
            result.origin.y = max(bounds.minY, bounds.maxY - result.height)
        }
        return result
    }

    /// Converts between Cocoa (bottom-left origin) and Accessibility (top-left origin) coordinates.
    /// The conversion is its own inverse.
    static func flipped(_ rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
