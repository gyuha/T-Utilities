import AppKit
import ApplicationServices
import IOKit.hid

public enum Permission: String, CaseIterable, Hashable, Sendable {
    case accessibility
    case inputMonitoring
    case screenRecording

    public var displayName: String {
        switch self {
        case .accessibility: "손쉬운 사용"
        case .inputMonitoring: "입력 모니터링"
        case .screenRecording: "화면 기록"
        }
    }

    /// Live TCC state (no change notification exists; poll when needed).
    @MainActor
    public var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }

    /// Shows the system prompt (first time only) and opens the matching System Settings pane.
    @MainActor
    public func request() {
        switch self {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        NSWorkspace.shared.open(settingsURL)
    }

    var settingsURL: URL {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
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
        let result = Set(Permission.allCases.filter(\.isGranted))
        if result != granted { granted = result }
    }

    public func isGranted(_ permission: Permission) -> Bool {
        granted.contains(permission)
    }

    public func request(_ permission: Permission) {
        permission.request()
    }
}
