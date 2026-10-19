import CoreGraphics

/// Pure geometry for the supported actions, in Cocoa screen coordinates (origin bottom-left of the
/// primary display). Logic follows Rectangle's ScreenDetection / MaximizeCalculation /
/// NextPrevDisplayCalculation with their default settings.
enum WindowLayout {
    struct Screen: Equatable {
        let frame: CGRect
        let visibleFrame: CGRect
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
