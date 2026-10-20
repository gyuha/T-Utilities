import AppKit
import ApplicationServices

/// The focused window of the frontmost app, controlled through the Accessibility API.
/// Frames are in Accessibility coordinates (top-left origin). Adapted from Rectangle's AccessibilityElement.
@MainActor
struct AXWindow {
    private static let enhancedUserInterface = "AXEnhancedUserInterface" as CFString

    let element: AXUIElement
    let app: AXUIElement

    static func frontmost() -> AXWindow? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        if let focused: AXUIElement = app.value(kAXFocusedWindowAttribute) {
            return AXWindow(element: focused, app: app)
        }
        if let windows: [AXUIElement] = app.value(kAXWindowsAttribute), let first = windows.first {
            return AXWindow(element: first, app: app)
        }
        return nil
    }

    /// The window under a point in Accessibility coordinates (top-left origin), e.g. where a drag started.
    static func at(_ point: CGPoint) -> AXWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        let window: AXUIElement? = (hit.value(kAXRoleAttribute) as String?) == (kAXWindowRole as String)
            ? hit : hit.value(kAXWindowAttribute)
        var pid: pid_t = 0
        guard let window, AXUIElementGetPid(window, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        return AXWindow(element: window, app: AXUIElementCreateApplication(pid))
    }

    var frame: CGRect? {
        guard let position: CGPoint = element.axValue(kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = element.axValue(kAXSizeAttribute, type: .cgSize) else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isSheet: Bool {
        (element.value(kAXRoleAttribute) as String?) == (kAXSheetRole as String)
    }

    var isResizable: Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success else {
            return true
        }
        return settable.boolValue
    }

    /// Size → position → size: macOS clamps sizes to the display the window is on, so moving across
    /// displays needs the second resize. AXEnhancedUserInterface (set by e.g. VoiceOver-aware apps)
    /// makes AX writes animate or fail, so it is turned off for the duration.
    func setFrame(_ target: CGRect) {
        let enhanced: Bool? = app.value(Self.enhancedUserInterface)
        if enhanced == true { AXUIElementSetAttributeValue(app, Self.enhancedUserInterface, kCFBooleanFalse) }
        defer {
            if enhanced == true { AXUIElementSetAttributeValue(app, Self.enhancedUserInterface, kCFBooleanTrue) }
        }
        set(size: target.size)
        set(position: target.origin)
        set(size: target.size)
    }

    func set(position: CGPoint) {
        var value = position
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
    }

    func set(size: CGSize) {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
    }
}

private extension AXUIElement {
    func value<T>(_ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func value<T>(_ attribute: CFString) -> T? {
        value(attribute as String)
    }

    func axValue<T>(_ attribute: String, type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue // swiftlint:disable:this force_cast — type checked above
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(axValue, type, pointer) ? pointer.pointee : nil
    }
}
