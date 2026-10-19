import AppKit

/// Menu bar icon: SF Symbol `cup.and.saucer` (outline/filled), optionally with steam drawn above it.
/// The cup has the same size and position in every state so switching modes doesn't make it jump.
enum AwakeIcon {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(filled: Bool, steam: Bool, size: CGFloat = 18) -> NSImage {
        let key = "\(filled)-\(steam)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(filled: filled, steam: steam, size: size)
        cache[key] = image
        return image
    }

    private static func render(filled: Bool, steam: Bool, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.66, weight: .regular)
            guard let cup = NSImage(
                systemSymbolName: filled ? "cup.and.saucer.fill" : "cup.and.saucer",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(config) else { return false }

            let cupRect = NSRect(
                x: (size - cup.size.width) / 2, y: 0.5,
                width: cup.size.width, height: cup.size.height
            )
            cup.draw(in: cupRect)
            guard steam else { return true }

            // Three small S-curves above the cup body (the body sits left of the handle).
            NSColor.black.setStroke()
            let bodyCenterX = cupRect.minX + cupRect.width * 0.42
            let base = cupRect.maxY + size * 0.03
            let top = size * 0.96
            for offset in -1...1 {
                let x = bodyCenterX + CGFloat(offset) * size * 0.17
                let height = top - base - (offset == 0 ? 0 : size * 0.06)
                let path = NSBezierPath()
                path.lineWidth = size * 0.075
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: x, y: base))
                path.curve(
                    to: NSPoint(x: x, y: base + height),
                    controlPoint1: NSPoint(x: x + size * 0.09, y: base + height * 0.33),
                    controlPoint2: NSPoint(x: x - size * 0.09, y: base + height * 0.66)
                )
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Awake"
        return image
    }
}
