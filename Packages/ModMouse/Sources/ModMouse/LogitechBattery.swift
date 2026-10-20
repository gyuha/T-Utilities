import Foundation
import IOKit
import IOKit.hid

// Logitech HID++ 2.0 battery reading, adapted from LinearMouse's HIDPP module and HIDPPBatteryObservation
// (MIT, © LinearMouse) — https://github.com/linearmouse/linearmouse

public struct BatteryReading: Equatable, Sendable {
    public enum ChargeState: Sendable { case unknown, discharging, charging, full }
    public let level: Int?
    public let chargeState: ChargeState
}

public struct MouseBatteryInfo: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let reading: BatteryReading
}

/// HID++ battery features in preference order, with the decoders LinearMouse uses.
enum BatteryFeature: UInt16, CaseIterable {
    case unifiedBattery = 0x1004
    case batteryStatus = 0x1000
    case batteryVoltage = 0x1001

    /// Function that returns the current state (events from the device use the same layout).
    var readFunction: UInt8 { self == .unifiedBattery ? 1 : 0 }

    func decode(_ payload: [UInt8]) -> BatteryReading? {
        switch self {
        case .batteryStatus:
            guard payload.count >= 3 else { return nil }
            return BatteryReading(level: Self.percentage(payload[0]), chargeState: Self.chargeState(payload[2]))
        case .unifiedBattery:
            guard payload.count >= 3 else { return nil }
            let approximate: Int? = [UInt8(1): 5, 2: 20, 4: 50, 8: 100][payload[1]]
            return BatteryReading(level: Self.percentage(payload[0]) ?? approximate, chargeState: Self.chargeState(payload[2]))
        case .batteryVoltage:
            guard payload.count >= 3 else { return nil }
            let millivolts = Int(payload[0]) << 8 | Int(payload[1])
            let level = Int((Double(min(4200, max(3500, millivolts)) - 3500) / 700 * 100).rounded())
            let flags = payload[2]
            let state: BatteryReading.ChargeState =
                flags & 0x80 == 0 ? .discharging : (flags & 0x03 == 3 ? .full : .charging)
            return BatteryReading(level: level, chargeState: state)
        }
    }

    private static func percentage(_ byte: UInt8) -> Int? {
        (1...100).contains(byte) ? Int(byte) : nil
    }

    private static func chargeState(_ byte: UInt8) -> BatteryReading.ChargeState {
        switch byte {
        case 0: .discharging
        case 1, 2, 4: .charging
        case 3: .full
        default: .unknown
        }
    }
}

/// Talks HID++ to Logitech receivers / devices through their vendor HID interface (usage page 0xFF00).
/// Opening that interface is non-exclusive and needs no permission.
@MainActor
final class LogitechBattery {
    private static let longReportID: UInt8 = 0x11
    private static let longReportLength = 20
    private static let softwareID: UInt8 = 0x08
    private static let timeout: Duration = .seconds(1)

    private struct Endpoint {
        let channel: Channel
        let index: UInt8
        let name: String
        let feature: BatteryFeature
        let featureIndex: UInt8
    }

    /// One opened vendor interface with its input-report buffer.
    private final class Channel {
        let device: IOHIDDevice
        let key: String
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        var pending: (id: Int, match: ([UInt8]) -> Bool, continuation: CheckedContinuation<[UInt8]?, Never>)?
        var nextRequestID = 0
        var onUnsolicited: (([UInt8]) -> Void)?

        init(device: IOHIDDevice, key: String) {
            self.device = device
            self.key = key
        }

        deinit { buffer.deallocate() }
    }

    var onChange: (([MouseBatteryInfo]) -> Void)?
    private(set) var batteries: [MouseBatteryInfo] = [] {
        didSet { if batteries != oldValue { onChange?(batteries) } }
    }

    private var manager: IOHIDManager?
    private var channels: [Channel] = []
    private var endpoints: [Endpoint] = []
    private var readings: [String: BatteryReading] = [:]

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x046D,
            kIOHIDPrimaryUsagePageKey: 0xFF00,
        ] as CFDictionary)
        self.manager = manager
    }

    func stop() {
        for channel in channels { close(channel) }
        channels = []
        endpoints = []
        readings = [:]
        manager = nil
        batteries = []
    }

    /// Re-discovers devices (cheap when nothing changed) and reads every battery once.
    func refresh() async {
        guard let manager else { return }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let keys = Set(devices.map(Self.key(for:)))
        // Also retry discovery while nothing answered (e.g. the mouse was asleep).
        if keys != Set(channels.map(\.key)) || endpoints.isEmpty {
            for channel in channels { close(channel) }
            channels = devices.compactMap(open)
            endpoints = []
            for channel in channels {
                endpoints += await discover(on: channel)
            }
        }
        for endpoint in endpoints {
            let payload = await request(endpoint.channel, index: endpoint.index, feature: endpoint.featureIndex,
                                        function: endpoint.feature.readFunction)
            // A sleeping mouse doesn't answer; keep its last reading.
            if let reading = payload.flatMap(endpoint.feature.decode) {
                readings[endpointID(endpoint)] = reading
            }
        }
        publish()
    }

    // MARK: - Discovery

    private func discover(on channel: Channel) async -> [Endpoint] {
        // Receivers route paired devices on indices 1…6; directly attached devices answer on 0xFF.
        var found: [Endpoint] = []
        for index: UInt8 in [1, 2, 3, 4, 5, 6, 0xFF] {
            guard await request(channel, index: index, feature: 0, function: 1, parameters: [0, 0, 0xAA]) != nil else { continue }
            for feature in BatteryFeature.allCases {
                guard let response = await request(channel, index: index, feature: 0, function: 0,
                                                   parameters: [UInt8(feature.rawValue >> 8), UInt8(feature.rawValue & 0xFF)]),
                      let featureIndex = response.first, featureIndex != 0 else { continue }
                let name = await deviceName(channel, index: index) ?? "Logitech"
                found.append(Endpoint(channel: channel, index: index, name: name, feature: feature, featureIndex: featureIndex))
                break
            }
            if index == 0xFF, !found.isEmpty { break }
        }
        return found
    }

    /// Feature 0x0005 DeviceName: function 0 = length, function 1 = chunk at offset.
    private func deviceName(_ channel: Channel, index: UInt8) async -> String? {
        guard let response = await request(channel, index: index, feature: 0, function: 0, parameters: [0x00, 0x05]),
              let featureIndex = response.first, featureIndex != 0,
              let length = await request(channel, index: index, feature: featureIndex, function: 0)?.first else { return nil }
        var bytes: [UInt8] = []
        while bytes.count < Int(length) {
            guard let chunk = await request(channel, index: index, feature: featureIndex, function: 1,
                                            parameters: [UInt8(bytes.count)]), !chunk.isEmpty else { break }
            bytes += chunk.prefix(Int(length) - bytes.count)
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Transport

    private func open(_ device: IOHIDDevice) -> Channel? {
        let maxOutput = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        guard maxOutput >= Self.longReportLength,
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
        let channel = Channel(device: device, key: Self.key(for: device))
        IOHIDDeviceRegisterInputReportCallback(device, channel.buffer, 64, { context, _, _, _, _, report, length in
            guard let context else { return }
            let channel = Unmanaged<Channel>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { LogitechBattery.receive(bytes, on: channel) }
        }, Unmanaged.passUnretained(channel).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        channel.onUnsolicited = { [weak self] bytes in self?.handleEvent(bytes, from: channel) }
        return channel
    }

    private func close(_ channel: Channel) {
        IOHIDDeviceRegisterInputReportCallback(channel.device, channel.buffer, 64, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(channel.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(channel.device, IOOptionBits(kIOHIDOptionsTypeNone))
        resolvePending(on: channel, with: nil)
    }

    private static func receive(_ bytes: [UInt8], on channel: Channel) {
        guard bytes.count >= 4 else { return }
        if let pending = channel.pending, pending.match(bytes) {
            channel.pending = nil
            let isError = (bytes[0] == 0x10 && bytes[2] == 0x8F) || bytes[2] == 0xFF
            pending.continuation.resume(returning: isError ? nil : Array(bytes[4...]))
        } else {
            channel.onUnsolicited?(bytes)
        }
    }

    /// Battery events from the device (software ID 0) update the reading without polling.
    private func handleEvent(_ bytes: [UInt8], from channel: Channel) {
        guard bytes[0] == Self.longReportID, bytes[3] & 0x0F == 0,
              let endpoint = endpoints.first(where: {
                  $0.channel === channel && $0.index == bytes[1] && $0.featureIndex == bytes[2]
              }),
              let reading = endpoint.feature.decode(Array(bytes[4...])) else { return }
        readings[endpointID(endpoint)] = reading
        publish()
    }

    private func request(_ channel: Channel, index: UInt8, feature: UInt8, function: UInt8,
                         parameters: [UInt8] = []) async -> [UInt8]? {
        guard channel.pending == nil else { return nil }
        let functionByte = function << 4 | Self.softwareID
        var report = [UInt8](repeating: 0, count: Self.longReportLength)
        report[0] = Self.longReportID
        report[1] = index
        report[2] = feature
        report[3] = functionByte
        report.replaceSubrange(4..<4 + parameters.count, with: parameters)

        channel.nextRequestID += 1
        let requestID = channel.nextRequestID
        return await withCheckedContinuation { continuation in
            channel.pending = (id: requestID, match: { bytes in
                guard bytes[1] == index else { return false }
                if bytes[0] == 0x10, bytes[2] == 0x8F { return true }           // HID++ 1.0 error (e.g. no device)
                if bytes[2] == 0xFF { return bytes[3] == feature && bytes[4] == functionByte } // HID++ 2.0 error
                return bytes[2] == feature && bytes[3] == functionByte
            }, continuation: continuation)
            let result = IOHIDDeviceSetReport(channel.device, kIOHIDReportTypeOutput, CFIndex(Self.longReportID),
                                              report, report.count)
            guard result == kIOReturnSuccess else {
                resolvePending(on: channel, with: nil)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                guard channel.pending?.id == requestID else { return }
                self?.resolvePending(on: channel, with: nil)
            }
        }
    }

    private func resolvePending(on channel: Channel, with value: [UInt8]?) {
        guard let pending = channel.pending else { return }
        channel.pending = nil
        pending.continuation.resume(returning: value)
    }

    private func publish() {
        batteries = endpoints.compactMap { endpoint in
            readings[endpointID(endpoint)].map { MouseBatteryInfo(id: endpointID(endpoint), name: endpoint.name, reading: $0) }
        }
    }

    private func endpointID(_ endpoint: Endpoint) -> String { "\(endpoint.channel.key)#\(endpoint.index)" }

    private static func key(for device: IOHIDDevice) -> String {
        let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        return "\(product)@\(location)"
    }
}
