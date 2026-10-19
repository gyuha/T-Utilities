import AppKit
import SwiftUI
import TUCore
import TUUI
import WhatCableCore
import WhatCableDarwinBackend

// Port, cable and charger diagnostics from WhatCable (MIT, © Darryl Morley) — https://github.com/darrylmorley/whatcable

/// USB-C / MagSafe port diagnostics. The popover shows one line; details open as a native submenu.
@MainActor
@Observable
public final class CableModule: TUModule {
    public static let descriptor = ModuleDescriptor(
        id: "cable",
        displayName: "Cable",
        symbol: "cable.connector",
        hasPopoverSection: true,
        conflictingBundleIDs: ["uk.whatcable.whatcable"]
    )

    /// Background refresh for the one-line summary; the popover also refreshes when it opens.
    static let refreshInterval: Duration = .seconds(15)

    @ObservationIgnored private var refresher: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    private(set) var reports: [PortReport] = []
    private(set) var summary = CableSummary(reports: [], chargingWatts: nil)
    private(set) var errorMessage: String?

    public init(context: ModuleContext) {}

    public func start() async throws {
        refresher = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    public func stop() async {
        refresher?.cancel()
        refresher = nil
        reports = []
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snapshot = try await makeDefaultSnapshotProvider().snapshot()
            reports = PortReport.build(from: snapshot)
            summary = CableSummary(reports: reports, chargingWatts: CableSummary.chargingWatts(from: snapshot))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Shell integration

    public func popoverWillShow() {
        Task { await refresh() }
    }

    public func makePopoverSection() -> AnyView? {
        AnyView(CableSectionView(module: self))
    }

    public func makeSettingsView() -> AnyView {
        AnyView(CableSettingsView(module: self))
    }

    func showMenu() {
        CableMenu.make(reports: reports).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private struct CableSectionView: View {
    let module: CableModule

    var body: some View {
        Button(action: module.showMenu) {
            SectionRow(symbol: "cable.connector", title: "USB-C", showsChevron: true) {
                HStack(spacing: 4) {
                    Text(module.summary.text)
                    if module.summary.hasWarning {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help("포트별 상세 정보")
    }
}

private struct CableSettingsView: View {
    let module: CableModule

    var body: some View {
        Form {
            Section("현재 포트") {
                if module.reports.isEmpty {
                    Text(module.errorMessage ?? "포트 정보를 읽는 중…").foregroundStyle(.secondary)
                }
                ForEach(module.reports) { report in
                    LabeledContent(report.name) {
                        HStack(spacing: 4) {
                            if report.hasWarning {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                            Text(report.headline).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("새로 고침") { Task { await module.refresh() } }
            }
            Section {
                Text("포트·케이블·충전기 정보는 WhatCable 엔진으로 읽습니다. 케이블 칩(e-marker)이 없는 케이블은 정보가 제한되고, \"케이블 병목\" 판정은 추정입니다. 팝오버의 USB-C 행을 누르면 포트별 상세가 서브메뉴로 열립니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
