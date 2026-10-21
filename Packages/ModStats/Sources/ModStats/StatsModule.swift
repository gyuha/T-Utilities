import AppKit
import SwiftUI
import TUCore
import TUUI

// Design reference only: exelban/stats (MIT, © Serhiy Mytrovtsiy) — https://github.com/exelban/stats

/// System CPU / memory at a glance plus top processes. Nothing runs in the background: a measurement
/// starts when the popover opens (one sample, a second one ~1 s later for CPU%) and then stops.
@MainActor
@Observable
public final class StatsModule: TUModule {
    public static let descriptor = ModuleDescriptor(
        id: "stats",
        displayName: "Stats",
        symbol: "gauge.with.dots.needle.33percent",
        hasPopoverSection: true,
        enabledByDefault: false
    )

    static let topCount = 8
    static let sampleInterval: Duration = .seconds(1)

    @ObservationIgnored private var measurement: Task<Void, Never>?
    private(set) var cpuPercent: Double?
    private(set) var memory: (used: UInt64, total: UInt64)?
    private(set) var topCPU: [ProcessUsage] = []
    private(set) var topMemory: [ProcessUsage] = []

    public init(context: ModuleContext) {}

    public func start() async throws {}

    public func stop() async {
        measurement?.cancel()
        measurement = nil
        cpuPercent = nil
        memory = nil
        topCPU = []
        topMemory = []
    }

    /// Two snapshots ~1 s apart; the first updates memory immediately, the second CPU and the process lists.
    func measure() {
        measurement?.cancel()
        measurement = Task { [weak self] in
            let first = await Task.detached(priority: .utility) { StatsSampler.takeSnapshot() }.value
            guard !Task.isCancelled, let self else { return }
            memory = (first.memoryUsed, first.memoryTotal)
            try? await Task.sleep(for: Self.sampleInterval)
            guard !Task.isCancelled else { return }
            let second = await Task.detached(priority: .utility) { StatsSampler.takeSnapshot() }.value
            guard !Task.isCancelled else { return }
            apply(from: first, to: second)
        }
    }

    private func apply(from first: StatsSampler.Snapshot, to second: StatsSampler.Snapshot) {
        memory = (second.memoryUsed, second.memoryTotal)
        cpuPercent = CPUTicks.usage(from: first.ticks, to: second.ticks)
        let usages = StatsMath.processUsage(
            previous: Dictionary(first.processes.map { ($0.pid, $0) }, uniquingKeysWith: { $1 }),
            current: second.processes,
            wallNanoseconds: second.wallNanoseconds &- first.wallNanoseconds,
            timebase: StatsSampler.timebase
        )
        topCPU = StatsMath.topByCPU(usages, limit: Self.topCount)
        topMemory = StatsMath.topByMemory(usages, limit: Self.topCount)
    }

    var summary: String { StatsMath.summaryText(cpu: cpuPercent, memory: memory) }

    // MARK: - Shell integration

    public func popoverWillShow() {
        measure()
    }

    public func makePopoverSection() -> AnyView? {
        AnyView(StatsSectionView(module: self))
    }

    public func makeSettingsView() -> AnyView {
        AnyView(StatsSettingsView(module: self))
    }

    func showMenu() {
        StatsMenu.make(topCPU: topCPU, topMemory: topMemory).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private struct StatsSectionView: View {
    let module: StatsModule

    var body: some View {
        Button(action: module.showMenu) {
            SectionRow(symbol: StatsModule.descriptor.symbol, title: "Stats", showsChevron: true) {
                Text(module.summary)
            }
        }
        .buttonStyle(.plain)
        .help("CPU·메모리 상위 프로세스")
    }
}

private struct StatsSettingsView: View {
    let module: StatsModule

    var body: some View {
        Form {
            Section {
                Text("팝오버를 열 때만 측정합니다(백그라운드 폴링 없음). CPU는 1초 간격 두 번 측정한 값이며, 프로세스 CPU는 코어 1개 기준(멀티스레드는 100% 초과 가능)입니다. 메모리는 활동 모니터와 같은 방식(앱 메모리 + 유선 + 압축)이고, 프로세스 메모리는 물리 풋프린트입니다. 읽을 수 없는 다른 사용자·시스템 프로세스는 제외됩니다. 팝오버의 Stats 행을 누르면 상위 프로세스 메뉴가 열립니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Native menu: top processes by CPU and by memory, plus Activity Monitor.
@MainActor
enum StatsMenu {
    static func make(topCPU: [ProcessUsage], topMemory: [ProcessUsage]) -> NSMenu {
        let menu = NSMenu()
        addSection(to: menu, title: "CPU 상위", rows: topCPU) { StatsMath.formatPercent($0.cpuPercent) }
        menu.addItem(.separator())
        addSection(to: menu, title: "메모리 상위", rows: topMemory) { StatsMath.formatProcessMemory($0.footprint) }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "활동 모니터 열기", action: #selector(MenuTarget.openActivityMonitor), keyEquivalent: "")
        open.target = MenuTarget.shared
        menu.addItem(open)
        return menu
    }

    private static func addSection(
        to menu: NSMenu, title: String, rows: [ProcessUsage], value: (ProcessUsage) -> String
    ) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if rows.isEmpty {
            let item = NSMenuItem(title: "측정 중…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for usage in rows {
            let app = NSRunningApplication(processIdentifier: usage.pid)
            let name = app?.localizedName ?? usage.name
            let item = NSMenuItem(title: "\(name) — \(value(usage))", action: nil, keyEquivalent: "")
            // GUI apps come to the front when clicked; other processes are shown greyed out.
            if let app, app.activationPolicy == .regular {
                item.action = #selector(MenuTarget.activate(_:))
                item.target = MenuTarget.shared
                item.representedObject = app
            } else {
                item.isEnabled = false
            }
            menu.addItem(item)
        }
    }

    @MainActor
    final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func activate(_ sender: NSMenuItem) {
            (sender.representedObject as? NSRunningApplication)?.activate()
        }

        @objc func openActivityMonitor() {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
    }
}
