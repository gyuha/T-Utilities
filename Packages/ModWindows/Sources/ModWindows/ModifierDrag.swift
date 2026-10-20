import CoreGraphics

/// Modifier keys that arm modifier-drag (move / resize a window from anywhere inside it).
struct DragModifiers: OptionSet, Sendable {
    let rawValue: Int

    static let control = DragModifiers(rawValue: 1 << 0)
    static let option = DragModifiers(rawValue: 1 << 1)
    static let shift = DragModifiers(rawValue: 1 << 2)
    static let command = DragModifiers(rawValue: 1 << 3)

    static let `default`: DragModifiers = [.option]

    /// A stored value with no known key would arm on every plain click, so it falls back to the default.
    static func stored(_ raw: Int) -> DragModifiers {
        let modifiers = DragModifiers(rawValue: raw & 0b1111)
        return modifiers.isEmpty ? .default : modifiers
    }

    /// Exactly these keys are down (Caps Lock, fn etc. are ignored), so ⌥ does not also fire on ⌥⌘.
    func matches(_ flags: CGEventFlags) -> Bool {
        var pressed: DragModifiers = []
        if flags.contains(.maskControl) { pressed.insert(.control) }
        if flags.contains(.maskAlternate) { pressed.insert(.option) }
        if flags.contains(.maskShift) { pressed.insert(.shift) }
        if flags.contains(.maskCommand) { pressed.insert(.command) }
        return pressed == self
    }
}

/// Frame math for modifier-drag. All frames and points use Accessibility coordinates (top-left origin).
enum ModifierDragLogic {
    static let minimumSize = CGSize(width: 100, height: 60)

    enum Horizontal { case left, right }
    enum Vertical { case top, bottom }

    struct Region: Equatable {
        let horizontal: Horizontal
        let vertical: Vertical
    }

    static func moved(_ start: CGRect, by delta: CGPoint) -> CGRect {
        start.offsetBy(dx: delta.x, dy: delta.y)
    }

    /// The window quadrant under the cursor; resizing drags that corner and anchors the opposite one.
    static func region(of point: CGPoint, in frame: CGRect) -> Region {
        Region(
            horizontal: point.x < frame.midX ? .left : .right,
            vertical: point.y < frame.midY ? .top : .bottom
        )
    }

    static func resized(_ start: CGRect, region: Region, by delta: CGPoint) -> CGRect {
        var frame = start
        switch region.horizontal {
        case .left:
            frame.size.width = max(minimumSize.width, start.width - delta.x)
            frame.origin.x = start.maxX - frame.width
        case .right:
            frame.size.width = max(minimumSize.width, start.width + delta.x)
        }
        switch region.vertical {
        case .top:
            frame.size.height = max(minimumSize.height, start.height - delta.y)
            frame.origin.y = start.maxY - frame.height
        case .bottom:
            frame.size.height = max(minimumSize.height, start.height + delta.y)
        }
        return frame
    }
}
