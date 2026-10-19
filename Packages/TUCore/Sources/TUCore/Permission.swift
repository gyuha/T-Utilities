import AppKit
import ApplicationServices
import IOKit.hid

public enum Permission: String, CaseIterable, Hashable, Sendable {
    case accessibility
    case inputMonitoring

    public var displayName: String {
        switch self {
        case .accessibility: "손쉬운 사용"
        case .inputMonitoring: "입력 모니터링"
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }
}

@MainActor
@Observable
public final class PermissionCenter {
    public private(set) var granted: Set<Permission> = []

    public init() {
        refresh()
    }

    public func refresh() {
        var result: Set<Permission> = []
        if AXIsProcessTrusted() { result.insert(.accessibility) }
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted { result.insert(.inputMonitoring) }
        if result != granted { granted = result }
    }

    public func isGranted(_ permission: Permission) -> Bool {
        granted.contains(permission)
    }

    /// Shows the system prompt (first time only) and opens the matching System Settings pane.
    public func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        NSWorkspace.shared.open(permission.settingsURL)
    }
}
