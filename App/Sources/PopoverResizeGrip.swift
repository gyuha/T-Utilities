import AppKit
import SwiftUI
import TUCore

/// Invisible corner grip that resizes the popover. The popover hangs from the menu bar, so it grows downward
/// and symmetrically in width: width changes by twice the horizontal drag distance, which keeps the
/// grip under the cursor. Tracks `NSEvent.mouseLocation` because the grip itself moves while dragging.
struct PopoverResizeGrip: NSViewRepresentable {
    @Binding var width: Double
    @Binding var listHeight: Double

    func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.onDrag = { start, mouse in
            width = (start.width + 2 * (mouse.x - start.mouse.x)).clamped(to: PopoverSize.widthRange)
            listHeight = (start.listHeight + (start.mouse.y - mouse.y)).clamped(to: PopoverSize.listHeightRange)
        }
        view.current = { (width, listHeight) }
        return view
    }

    func updateNSView(_ view: GripView, context: Context) {}

    final class GripView: NSView {
        var onDrag: ((_ start: (mouse: CGPoint, width: Double, listHeight: Double), _ mouse: CGPoint) -> Void)?
        var current: (() -> (Double, Double))?
        private var start: (mouse: CGPoint, width: Double, listHeight: Double)?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

        override func mouseDown(with event: NSEvent) {
            let (width, listHeight) = current?() ?? (0, 0)
            start = (NSEvent.mouseLocation, width, listHeight)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            onDrag?(start, NSEvent.mouseLocation)
        }

        override func mouseUp(with event: NSEvent) { start = nil }
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<CGFloat>) -> Double {
        min(max(self, Double(range.lowerBound)), Double(range.upperBound))
    }
}
