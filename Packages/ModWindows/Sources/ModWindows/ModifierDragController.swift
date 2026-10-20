import AppKit

// Idea from easy-move-resize (MIT, © Daniel Marcotte): hold a modifier and drag anywhere in a window to move it,
// right-drag to resize it. https://github.com/dmarcotte/easy-move-resize

/// Session event tap behind modifier-drag. It swallows the armed mouse-down/drag/up so the app under the
/// cursor never sees the click, and moves/resizes the window under the cursor through the Accessibility API.
@MainActor
final class ModifierDragController {
    private enum Kind { case move, resize(ModifierDragLogic.Region) }

    private struct Session {
        let window: AXWindow
        let kind: Kind
        let startFrame: CGRect
        let startCursor: CGPoint
    }

    var modifiers: DragModifiers = .default

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var session: Session?

    private static let mask: CGEventMask = [
        CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp,
        .rightMouseDown, .rightMouseDragged, .rightMouseUp,
    ].reduce(0) { $0 | (1 << $1.rawValue) }

    func start() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<ModifierDragController>.fromOpaque(userInfo).takeUnretainedValue()
            // The tap's source lives on the main run loop.
            let swallow = MainActor.assumeIsolated { controller.handle(type, event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        session = nil
    }

    /// Returns whether the event is swallowed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown, .rightMouseDown:
            session = nil
            guard modifiers.matches(event.flags), let started = begin(isResize: type == .rightMouseDown, at: event.location) else {
                return false
            }
            session = started
            return true
        case .leftMouseDragged, .rightMouseDragged:
            guard let session else { return false }
            update(session, cursor: event.location)
            return true
        case .leftMouseUp, .rightMouseUp:
            guard session != nil else { return false }
            session = nil
            return true
        default:
            return false
        }
    }

    private func begin(isResize: Bool, at cursor: CGPoint) -> Session? {
        guard let window = AXWindow.at(cursor), !window.isSheet, let frame = window.frame else { return nil }
        if isResize, !window.isResizable { return nil }
        _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        let kind: Kind = isResize ? .resize(ModifierDragLogic.region(of: cursor, in: frame)) : .move
        return Session(window: window, kind: kind, startFrame: frame, startCursor: cursor)
    }

    private func update(_ session: Session, cursor: CGPoint) {
        let delta = CGPoint(x: cursor.x - session.startCursor.x, y: cursor.y - session.startCursor.y)
        switch session.kind {
        case .move:
            session.window.set(position: ModifierDragLogic.moved(session.startFrame, by: delta).origin)
        case .resize(let region):
            let target = ModifierDragLogic.resized(session.startFrame, region: region, by: delta)
            // Size first, then position: the order keeps the anchored corner fixed in apps that clamp sizes.
            session.window.set(size: target.size)
            session.window.set(position: target.origin)
        }
    }
}
