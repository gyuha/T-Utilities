import Testing
@testable import ModMouse

struct PointerSpeedTests {
    @Test func matchesLinearMouseResolutionScale() {
        #expect(PointerTuner.resolution(forSpeed: 0) == 1200)
        #expect(abs(PointerTuner.resolution(forSpeed: 1) - 40) < 0.0001)
        // The user's LinearMouse speed 0.08.
        #expect(abs(PointerTuner.resolution(forSpeed: 0.08) - 361.45) < 0.01)
    }
}

struct ScrollTransformTests {
    @Test func passesThroughWhenInactiveOrZero() {
        #expect(ScrollOptions.transformedLines(delta: 3, options: .init(reverse: false, lines: 0)) == nil)
        #expect(ScrollOptions.transformedLines(delta: 0, options: .init(reverse: true, lines: 3)) == nil)
    }

    @Test func reversesAndLinearizes() {
        #expect(ScrollOptions.transformedLines(delta: 2, options: .init(reverse: true, lines: 0)) == -2)
        #expect(ScrollOptions.transformedLines(delta: -7, options: .init(reverse: false, lines: 3)) == -3)
        #expect(ScrollOptions.transformedLines(delta: 1, options: .init(reverse: true, lines: 3)) == -3)
    }
}

struct BatteryDecodeTests {
    @Test func batteryStatusFromG304() {
        // Real G304 reply: 90 %, next level 50 %, discharging.
        #expect(BatteryFeature.batteryStatus.decode([0x5A, 0x32, 0x00]) == BatteryReading(level: 90, chargeState: .discharging))
    }

    @Test func unifiedBatteryFallsBackToLevelFlags() {
        #expect(BatteryFeature.unifiedBattery.decode([0, 0x04, 1]) == BatteryReading(level: 50, chargeState: .charging))
    }

    @Test func voltageMapsLinearly() {
        // 3850 mV → 50 %, not charging.
        #expect(BatteryFeature.batteryVoltage.decode([0x0F, 0x0A, 0x00]) == BatteryReading(level: 50, chargeState: .discharging))
        #expect(BatteryFeature.batteryVoltage.decode([0x10, 0x68, 0x83]) == BatteryReading(level: 100, chargeState: .full))
    }

    @Test func shortNameAndSymbol() {
        #expect(MouseModule.shortName("G304 Lightspeed Wireless Gaming Mouse") == "G304")
        #expect(MouseModule.batterySymbol(.init(level: 90, chargeState: .discharging)) == "battery.100percent")
        #expect(MouseModule.batterySymbol(.init(level: 20, chargeState: .discharging)) == "battery.25percent")
    }
}
