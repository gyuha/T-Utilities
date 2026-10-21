import AppKit

/// Menu bar icon: a 2×2 grid of rounded squares drawn as a template image.
/// Every state shares the same geometry; only which squares are filled changes.
public enum GridIcon {
    /// Squares in reading order: top-left, top-right, bottom-left, bottom-right.
    public static func image(filled: [Bool] = [false, false, false, false], size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            // 7pt squares with a 2pt gap in an 18pt canvas land on whole pixels at 1x and 2x.
            let side = (size / 18) * 7
            let gap = (size / 18) * 2
            let origin = (size - 2 * side - gap) / 2
            let line = max(1, (size / 18).rounded())
            NSColor.black.set()
            for index in 0..<4 {
                let x = origin + CGFloat(index % 2) * (side + gap)
                let y = origin + CGFloat(index / 2) * (side + gap)
                let rect = NSRect(x: x, y: y, width: side, height: side)
                if index < filled.count, filled[index] {
                    NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
                } else {
                    let path = NSBezierPath(
                        roundedRect: rect.insetBy(dx: line / 2, dy: line / 2),
                        xRadius: 1, yRadius: 1
                    )
                    path.lineWidth = line
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
