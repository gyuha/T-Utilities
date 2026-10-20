import AppKit
import CoreGraphics

// Button actions and scroll transforms adapted from LinearMouse (MIT, © LinearMouse)
// https://github.com/linearmouse/linearmouse — DockKit notifications, reverse and linear scrolling.

public enum MouseAction: String, CaseIterable, Identifiable, Sendable {
    case passThrough
    case missionControl
    case showDesktop
    case appExpose

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .passThrough: "기본 동작"
        case .missionControl: "Mission Control"
        case .showDesktop: "바탕화면 보기"
        case .appExpose: "앱 윈도우"
        }
    }

    /// Dock notifications used by LinearMouse's DockKit (private `CoreDockSendNotification`).
    private var dockNotification: String? {
        switch self {
        case .passThrough: nil
        case .missionControl: "com.apple.expose.awake"
        case .showDesktop: "com.apple.showdesktop.awake"
        case .appExpose: "com.apple.expose.front.awake"
        }
    }

    @MainActor
    func perform() {
        guard let dockNotification, let send = Self.coreDockSendNotification else { return }
        _ = send(dockNotification as CFString, 0)
    }

    private typealias SendNotification = @convention(c) (CFString, Int32) -> Int32
    @MainActor private static let coreDockSendNotification: SendNotification? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let symbol = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: SendNotification.self)
    }()
}

/// Scroll options for discrete wheels only (trackpads and Magic Mouse send continuous events and are left alone).
struct ScrollOptions: Equatable {
    var reverse: Bool
    /// Lines per wheel notch; 0 keeps macOS' accelerated scrolling.
    var lines: Int

    var isActive: Bool { reverse || lines > 0 }

    /// Vertical delta (in lines) after the transform, or nil when the event should pass unchanged.
    static func transformedLines(delta: Int64, options: ScrollOptions) -> Int64? {
        guard delta != 0, options.isActive else { return nil }
        var result = options.lines > 0 ? delta.signum() * Int64(options.lines) : delta
        if options.reverse { result = -result }
        return result
    }
}

/// One session event tap for side-button mappings and wheel transforms. Runs on the main run loop.
@MainActor
final class MouseEventTap {
    var buttonActions: [Int: MouseAction] = [:]
    var scroll = ScrollOptions(reverse: false, lines: 0)

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isInstalled: Bool { port != nil }

    /// Fails without Accessibility permission.
    func install() -> Bool {
        guard port == nil else { return true }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
        return true
    }

    func uninstall() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<MouseEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        // The tap's run loop source is on the main run loop, so this callback runs on the main thread.
        nonisolated(unsafe) let event = event
        let keep = MainActor.assumeIsolated { tap.handle(type, event) }
        return keep ? Unmanaged.passUnretained(event) : nil
    }

    /// Mutates `event` in place; returns false to swallow it.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard let action = buttonActions[button], action != .passThrough else { break }
            // Fire on press; swallow the whole press/drag/release so apps don't also see Back/Forward.
            if type == .otherMouseDown {
                DispatchQueue.main.async { action.perform() }
            }
            return false
        case .scrollWheel:
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
                  let lines = ScrollOptions.transformedLines(
                      delta: event.getIntegerValueField(.scrollWheelEventDeltaAxis1), options: scroll
                  ) else { break }
            // Read every field before writing: setting one delta field can make macOS recompute the others.
            let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let point = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lines)
            if scroll.lines > 0 {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
            } else {
                // Reverse only: flip the already-accelerated values instead of replacing them.
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixed)
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -point)
            }
        default:
            break
        }
        return true
    }
}
