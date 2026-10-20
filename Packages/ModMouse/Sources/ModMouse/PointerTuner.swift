import Foundation
import IOKit
import IOKit.hid

// Pointer speed/acceleration via IOHIDServiceClient properties, adapted from LinearMouse's PointerKit
// (MIT, © LinearMouse) — https://github.com/linearmouse/linearmouse

/// Applies pointer speed and acceleration to external mice and restores the original values on `restore()`.
/// Speed maps to `HIDPointerResolution` (lower = faster) exactly like LinearMouse, so its settings carry over.
@MainActor
final class PointerTuner {
    struct Settings: Equatable {
        /// 0…1, LinearMouse scale.
        var speed: Double
        /// 0…3 (system slider range), written to `HIDMouseAcceleration`.
        var acceleration: Double
    }

    private struct Original {
        let resolution: Double?
        let acceleration: Double?
    }

    static let resolutionKey = "HIDPointerResolution"
    static let accelerationKey = "HIDMouseAcceleration"
    static let accelerationTypeKey = "HIDPointerAccelerationType"
    /// Resolution macOS uses for mice when the property is absent.
    static let defaultResolution = 400.0
    private nonisolated static let speedRange = 1.0 / 1200 ... 1.0 / 40

    private let client: IOHIDEventSystemClient
    private var originals: [UInt64: Original] = [:]
    private var deviceWatcher: IOHIDManager?

    init() {
        client = Self.makeAdminClient() ?? IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    }

    nonisolated static func resolution(forSpeed speed: Double) -> Double {
        let clamped = min(1, max(0, speed))
        return 1 / (speedRange.lowerBound + clamped * (speedRange.upperBound - speedRange.lowerBound))
    }

    /// Applies to every mouse currently connected (trackpads use a different acceleration type and are skipped).
    func apply(_ settings: Settings) {
        for service in mouseServices() {
            guard let id = IOHIDServiceClientGetRegistryID(service) as? UInt64 else { continue }
            if originals[id] == nil {
                originals[id] = Original(
                    resolution: Self.fixed(service, Self.resolutionKey),
                    acceleration: Self.fixed(service, Self.accelerationKey)
                )
            }
            Self.setFixed(service, Self.resolutionKey, Self.resolution(forSpeed: settings.speed).clamped(10, 1995))
            Self.setFixed(service, Self.accelerationKey, settings.acceleration.clamped(0, 40))
        }
    }

    func restore() {
        for service in mouseServices() {
            guard let id = IOHIDServiceClientGetRegistryID(service) as? UInt64, let original = originals[id] else { continue }
            Self.setFixed(service, Self.resolutionKey, original.resolution ?? Self.defaultResolution)
            if let acceleration = original.acceleration {
                Self.setFixed(service, Self.accelerationKey, acceleration)
            }
        }
        originals.removeAll()
    }

    /// Calls `onChange` (debounced by the caller) when mice are attached, e.g. receiver plugged in or wake from sleep.
    func watchDevices(_ onChange: @escaping @MainActor () -> Void) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
        let box = Unmanaged.passRetained(CallbackBox(onChange)).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let callback = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().callback
            MainActor.assumeIsolated { callback() }
        }, box)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        deviceWatcher = manager
        watcherContext = box
    }

    private var watcherContext: UnsafeMutableRawPointer?

    func stopWatching() {
        if let deviceWatcher {
            IOHIDManagerUnscheduleFromRunLoop(deviceWatcher, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerRegisterDeviceMatchingCallback(deviceWatcher, nil, nil)
        }
        if let watcherContext {
            Unmanaged<CallbackBox>.fromOpaque(watcherContext).release()
        }
        deviceWatcher = nil
        watcherContext = nil
    }

    private func mouseServices() -> [IOHIDServiceClient] {
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return services.filter {
            IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0
                && (IOHIDServiceClientCopyProperty($0, Self.accelerationTypeKey as CFString) as? String) == Self.accelerationKey
        }
    }

    /// The public "simple" client can set acceleration but not resolution; LinearMouse uses this private admin client.
    private static func makeAdminClient() -> IOHIDEventSystemClient? {
        typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<IOHIDEventSystemClient>?
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let symbol = dlsym(handle, "IOHIDEventSystemClientCreate") else { return nil }
        return unsafeBitCast(symbol, to: Create.self)(kCFAllocatorDefault)?.takeRetainedValue()
    }

    private static func fixed(_ service: IOHIDServiceClient, _ key: String) -> Double? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? Int).map { Double($0) / 65536 }
    }

    @discardableResult
    private static func setFixed(_ service: IOHIDServiceClient, _ key: String, _ value: Double) -> Bool {
        IOHIDServiceClientSetProperty(service, key as CFString, Int(value * 65536) as CFNumber)
    }
}

final class CallbackBox {
    let callback: @MainActor () -> Void
    init(_ callback: @escaping @MainActor () -> Void) { self.callback = callback }
}

extension Double {
    func clamped(_ lower: Double, _ upper: Double) -> Double { Swift.min(upper, Swift.max(lower, self)) }
}
