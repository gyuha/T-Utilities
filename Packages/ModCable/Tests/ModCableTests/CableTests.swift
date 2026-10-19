import Foundation
import Testing
import WhatCableCore
import WhatCableDarwinBackend
@testable import ModCable

struct CableSummaryTests {
    func report(connected: Bool, warning: Bool = false) -> PortReport {
        PortReport(
            id: UUID().uuidString, name: "Port", isConnected: connected, headline: "", subtitle: "", groups: [],
            verdicts: warning ? [.init(title: "충전", summary: "", detail: "", isWarning: true)] : [],
            thunderboltFabric: [], tunnels: [], connectedDevices: [], trustFlags: []
        )
    }

    @Test func textCountsConnectedPortsAndWatts() {
        #expect(CableSummary(reports: [report(connected: false)], chargingWatts: nil).text == "연결 없음")
        let summary = CableSummary(reports: [report(connected: true), report(connected: false)], chargingWatts: 90)
        #expect(summary.text == "1개 연결 · 90W")
        #expect(!summary.hasWarning)
        #expect(CableSummary(reports: [report(connected: true, warning: true)], chargingWatts: nil).hasWarning)
    }
}

/// Reads this Mac's real ports through the vendored WhatCable backend (no fixtures needed).
@MainActor
struct LiveSnapshotTests {
    @Test func buildsOneReportPerPort() async throws {
        let snapshot = try await makeDefaultSnapshotProvider().snapshot()
        let reports = PortReport.build(from: snapshot)
        #expect(reports.count == snapshot.ports.count)
        #expect(reports.allSatisfy { !$0.headline.isEmpty })
    }
}
