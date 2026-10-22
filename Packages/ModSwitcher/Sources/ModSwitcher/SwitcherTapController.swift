import AppKit

/// Session event tap behind the switcher. Only trigger+Tab and, while the switcher is open, ←/→/Esc/Tab are
/// swallowed; every other event passes through untouched. The UI and Accessibility work runs after the callback
/// returns (the callback only runs `SwitcherKeyMachine`).
@MainActor
final class SwitcherTapController {
    /// Called on the main actor after the tap callback returned, in event order.
    var onCommand: ((SwitcherCommand) -> Void)?

    var trigger: SwitcherTrigger = .option {
        didSet {
            guard trigger != oldValue else { return }
            machine.trigger = trigger
            // A half-finished switch with the old trigger would never see its release.
            cancelActiveSession()
        }
    }

    private var machine = SwitcherKeyMachine()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var supervisor: Task<Void, Never>?

    /// How long keystrokes can stall after Accessibility is lost while the tap is active.
    static let tapCheckInterval: Duration = .seconds(3)

    private static let mask: CGEventMask = [CGEventType.keyDown, .flagsChanged].reduce(0) { $0 | (1 << $1.rawValue) }

    /// Installs the tap when possible and removes it as soon as event access is lost. An active tap whose app
    /// loses Accessibility (revoked, or the running bundle replaced by an update) stalls every keystroke
    /// system-wide, and `AXIsProcessTrusted` can report a stale grant — hence the real tap probe (same as the
    /// modifier-drag tap in the Windows module).
    func start() {
        guard supervisor == nil else { return }
        machine.trigger = trigger
        install()
        supervisor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tapCheckInterval)
                guard let self, !Task.isCancelled else { return }
                if tap != nil {
                    if await !Self.canCreateEventTap() { uninstall() }
                } else {
                    install()
                }
            }
        }
    }

    func stop() {
        supervisor?.cancel()
        supervisor = nil
        uninstall()
    }

    private func install() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<SwitcherTapController>.fromOpaque(userInfo).takeUnretainedValue()
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

    private func uninstall() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        cancelActiveSession()
    }

    /// Creates and immediately discards a tap off the main thread; fails once Accessibility is gone.
    private nonisolated static func canCreateEventTap() async -> Bool {
        await Task.detached(priority: .utility) {
            guard let probe = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
                callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil
            ) else { return false }
            CFMachPortInvalidate(probe)
            return true
        }.value
    }

    /// Returns whether the event is swallowed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let input: SwitcherKeyMachine.Input
        switch type {
        case .keyDown:
            input = .keyDown(SwitcherKey(keyCode: event.getIntegerValueField(.keyboardEventKeycode)))
        case .flagsChanged:
            input = .flagsChanged
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Events were lost, so the modifier release may have been too.
            cancelActiveSession()
            return false
        default:
            return false
        }
        let decision = machine.handle(input, flags: event.flags)
        if let command = decision.command { dispatch(command) }
        return decision.swallow
    }

    private func cancelActiveSession() {
        guard machine.isActive else { return }
        machine.reset()
        dispatch(.cancel)
    }

    /// FIFO on the main queue, so show → commit of a quick tap keeps its order.
    private func dispatch(_ command: SwitcherCommand) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onCommand?(command) }
        }
    }
}
