import Foundation
import Testing
@testable import ModClock

struct ClockModuleTests {
    // 2026-01-15 05:33:00 UTC
    let date = Date(timeIntervalSince1970: 1_768_455_180)

    @Test func formatsTwentyFourHourTimeInTargetZone() {
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(ClockModule.format(date, timeZone: newYork, label: "NY") == "NY 00:33")
        #expect(ClockModule.format(date, timeZone: newYork, label: nil) == "00:33")
        #expect(ClockModule.format(date, timeZone: TimeZone(identifier: "Asia/Seoul")!, label: "") == "14:33")
    }

    @Test(arguments: [
        ("America/New_York", "NY"),
        ("America/Los_Angeles", "LA"),
        ("Europe/London", "LON"),
        ("Asia/Seoul", "SEO"),
        ("UTC", "UTC"),
    ])
    func derivesLabelFromCity(id: String, expected: String) {
        #expect(ClockModule.derivedLabel(for: id) == expected)
    }
}
