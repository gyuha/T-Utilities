import Foundation
import IOKit.pwr_mgt

enum AwakeMode: String, CaseIterable, Sendable {
    case off, manual, auto

    var displayName: String {
        switch self {
        case .off: "끔"
        case .manual: "수동"
        case .auto: "자동"
        }
    }
}

enum AwakePolicy {
    /// Whether sleep should be prevented right now.
    /// - Parameters:
    ///   - manualUntil: end of the manual session; `nil` = unlimited.
    ///   - lastAgentActivity: last time an agent was seen working (auto mode).
    ///   - grace: how long to keep holding after the last agent activity.
    static func shouldHold(
        mode: AwakeMode,
        manualUntil: Date?,
        lastAgentActivity: Date?,
        now: Date,
        grace: TimeInterval
    ) -> Bool {
        switch mode {
        case .off:
            false
        case .manual:
            manualUntil.map { now < $0 } ?? true
        case .auto:
            lastAgentActivity.map { now.timeIntervalSince($0) < grace } ?? false
        }
    }
}

/// Holds a "prevent idle system sleep" power assertion while `isHeld` is true.
/// The OS drops the assertion automatically if the process dies.
@MainActor
final class SleepAssertion {
    private var assertionID: IOPMAssertionID?

    var isHeld: Bool {
        assertionID != nil
    }

    func set(_ hold: Bool, reason: String) {
        if hold, assertionID == nil {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionID = id
            }
        } else if !hold, let id = assertionID {
            IOPMAssertionRelease(id)
            assertionID = nil
        }
    }
}
