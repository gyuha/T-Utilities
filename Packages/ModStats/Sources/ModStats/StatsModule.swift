import AppKit
import SwiftUI
import TUCore
import TUUI

// Design reference only: exelban/stats (MIT, © Serhiy Mytrovtsiy) — https://github.com/exelban/stats

/// System CPU / memory at a glance; the popover row expands into a small dashboard (disk, network, optional GPU,
/// top processes). Nothing runs in the background: measuring starts when the popover opens (a second sample ~1 s
/// later for the rates), repeats every ~2 s only while the section is expanded, and stops when the popover closes.
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

    static let topCount = 5
    static let firstInterval: Duration = .seconds(1)
    static let refreshInterval: Duration = .seconds(2)

    @ObservationIgnored private let settings: ModuleSettings
    @ObservationIgnored private var measurement: Task<Void, Never>?
    @ObservationIgnored private var isPopoverShown = false
    private(set) var cpuPercent: Double?
    private(set) var memory: (used: UInt64, total: UInt64)?
    private(set) var disk: (used: UInt64, total: UInt64)?
    private(set) var networkRate: NetworkRate?
    private(set) var gpuPercent: Double?
    private(set) var topCPU: [ProcessUsage] = []
    private(set) var topMemory: [ProcessUsage] = []

    var isExpanded: Bool {
        didSet {
            settings.set(isExpanded, for: "expanded")
            // Expanding needs the extra readings right away; collapsing lets the running loop end by itself.
            if isExpanded && isPopoverShown { measure() }
        }
    }
    var showsCPU: Bool {
        didSet { settings.set(showsCPU, for: "showsCPU") }
    }
    var showsMemory: Bool {
        didSet { settings.set(showsMemory, for: "showsMemory") }
    }
    var showsDisk: Bool {
        didSet { settings.set(showsDisk, for: "showsDisk") }
    }
    var showsNetwork: Bool {
        didSet { settings.set(showsNetwork, for: "showsNetwork") }
    }
    /// Reads an undocumented IOKit value, so it is off unless the user asks for it.
    var showsGPU: Bool {
        didSet { settings.set(showsGPU, for: "showsGPU") }
    }

    public init(context: ModuleContext) {
        settings = context.settings
        isExpanded = context.settings.value("expanded", default: false)
        showsCPU = context.settings.value("showsCPU", default: true)
        showsMemory = context.settings.value("showsMemory", default: true)
        showsDisk = context.settings.value("showsDisk", default: true)
        showsNetwork = context.settings.value("showsNetwork", default: true)
        showsGPU = context.settings.value("showsGPU", default: false)
    }

    public func start() async throws {}

    public func stop() async {
        measurement?.cancel()
        measurement = nil
        isPopoverShown = false
        cpuPercent = nil
        memory = nil
        disk = nil
        networkRate = nil
        gpuPercent = nil
        topCPU = []
        topMemory = []
    }

    /// Collapsed, only CPU and memory are read (cheap); the dashboard adds processes and the enabled extras.
    private var scope: StatsSampler.Scope {
        StatsSampler.Scope(
            processes: isExpanded,
            network: isExpanded && showsNetwork,
            disk: isExpanded && showsDisk,
            gpu: isExpanded && showsGPU
        )
    }

    private static func sample(_ scope: StatsSampler.Scope) async -> StatsSampler.Snapshot {
        await Task.detached(priority: .utility) { StatsSampler.takeSnapshot(scope) }.value
    }

    /// One snapshot now, then one every second/refresh interval. Without the dashboard it stops after the first pair.
    func measure() {
        measurement?.cancel()
        measurement = Task { [weak self] in
            guard let self else { return }
            var previous = await Self.sample(scope)
            guard !Task.isCancelled else { return }
            memory = (previous.memoryUsed, previous.memoryTotal)
            disk = previous.disk
            gpuPercent = previous.gpuPercent
            var interval = Self.firstInterval
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                let current = await Self.sample(scope)
                guard !Task.isCancelled else { return }
                apply(from: previous, to: current)
                guard isExpanded else { return }
                previous = current
                interval = Self.refreshInterval
            }
        }
    }

    private func apply(from first: StatsSampler.Snapshot, to second: StatsSampler.Snapshot) {
        memory = (second.memoryUsed, second.memoryTotal)
        disk = second.disk
        gpuPercent = second.gpuPercent
        cpuPercent = CPUTicks.usage(from: first.ticks, to: second.ticks)
        let wallNanoseconds = second.wallNanoseconds &- first.wallNanoseconds
        networkRate = StatsMath.networkRate(
            previous: first.network, current: second.network, seconds: Double(wallNanoseconds) / 1_000_000_000
        )
        let usages = StatsMath.processUsage(
            previous: Dictionary(first.processes.map { ($0.pid, $0) }, uniquingKeysWith: { $1 }),
            current: second.processes,
            wallNanoseconds: wallNanoseconds,
            timebase: StatsSampler.timebase
        )
        topCPU = StatsMath.topByCPU(usages, limit: Self.topCount)
        topMemory = StatsMath.topByMemory(usages, limit: Self.topCount)
    }

    var summary: String { StatsMath.summaryText(cpu: cpuPercent, memory: memory) }

    // MARK: - Shell integration

    public func popoverWillShow() {
        isPopoverShown = true
        measure()
    }

    public func popoverDidClose() {
        isPopoverShown = false
        measurement?.cancel()
        measurement = nil
    }

    public func makePopoverSection() -> AnyView? {
        AnyView(StatsSectionView(module: self))
    }

    public func makeSettingsView() -> AnyView {
        AnyView(StatsSettingsView(module: self))
    }
}

private struct StatsSectionView: View {
    let module: StatsModule

    var body: some View {
        VStack(spacing: 0) {
            Button { module.isExpanded.toggle() } label: {
                SectionRow(symbol: StatsModule.descriptor.symbol, title: "Stats") {
                    HStack(spacing: 8) {
                        Text(module.summary)
                        Image(systemName: module.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("시스템 상태·상위 프로세스")

            if module.isExpanded {
                StatsDashboard(module: module)
            }
        }
    }
}

private struct StatsDashboard: View {
    let module: StatsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if module.showsCPU {
                GaugeRow(symbol: "cpu", title: "CPU", fraction: module.cpuPercent.map { $0 / 100 },
                         value: module.cpuPercent.map(StatsMath.formatPercent) ?? "…")
            }
            if module.showsMemory {
                GaugeRow(symbol: "memorychip", title: "메모리",
                         fraction: module.memory.map { StatsMath.fraction(used: $0.used, total: $0.total) },
                         value: module.memory.map { StatsMath.memoryText(used: $0.used, total: $0.total) } ?? "…")
            }
            if module.showsDisk {
                GaugeRow(symbol: "internaldrive", title: "디스크",
                         fraction: module.disk.map { StatsMath.fraction(used: $0.used, total: $0.total) },
                         value: module.disk.map { StatsMath.memoryText(used: $0.used, total: $0.total) } ?? "…")
            }
            if module.showsGPU {
                GaugeRow(symbol: "display", title: "GPU", fraction: module.gpuPercent.map { $0 / 100 },
                         value: module.gpuPercent.map(StatsMath.formatPercent) ?? "—")
            }
            if module.showsNetwork {
                GaugeRow(symbol: "arrow.up.arrow.down", title: "네트워크", fraction: nil,
                         value: module.networkRate.map(StatsMath.networkText) ?? "…")
            }

            ProcessList(title: "CPU 상위", rows: module.topCPU) { StatsMath.formatPercent($0.cpuPercent) }
            ProcessList(title: "메모리 상위", rows: module.topMemory) { StatsMath.formatProcessMemory($0.footprint) }

            Button("활동 모니터 열기") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// Icon, name, optional usage bar and a value. Rows without a natural 0–100% scale (network) omit the bar.
private struct GaugeRow: View {
    let symbol: String
    let title: String
    let fraction: Double?
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
            Spacer(minLength: 8)
            if let fraction {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .frame(width: 60)
            }
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// Top processes with a value each. GUI apps come to the front when clicked; other processes are plain text.
private struct ProcessList: View {
    let title: String
    let rows: [ProcessUsage]
    let value: (ProcessUsage) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if rows.isEmpty {
                Text("측정 중…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(rows) { usage in
                let app = NSRunningApplication(processIdentifier: usage.pid)
                let row = HStack {
                    Text(app?.localizedName ?? usage.name)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(value(usage))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                if let app, app.activationPolicy == .regular {
                    Button { app.activate() } label: { row.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
    }
}

private struct StatsSettingsView: View {
    @Bindable var module: StatsModule

    var body: some View {
        Form {
            Section {
                Text("팝오버를 열 때만 측정합니다(백그라운드 폴링 없음). Stats 행을 누르면 펼쳐지고, 펼쳐진 동안에만 약 2초마다 갱신합니다. CPU·네트워크는 두 번의 측정 사이 변화량으로 계산합니다. 프로세스 CPU는 코어 1개 기준(멀티스레드는 100% 초과 가능)입니다. 메모리는 활동 모니터와 같은 방식(앱 메모리 + 유선 + 압축)이고, 프로세스 메모리는 물리 풋프린트입니다. 읽을 수 없는 다른 사용자·시스템 프로세스는 제외됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("펼친 화면에 표시") {
                Toggle("CPU", isOn: $module.showsCPU)
                Toggle("메모리", isOn: $module.showsMemory)
                Toggle("디스크", isOn: $module.showsDisk)
                Toggle("네트워크", isOn: $module.showsNetwork)
                Toggle("GPU", isOn: $module.showsGPU)
                Text("GPU 사용률은 공식 API가 아닌 IOKit 내부 값(IOAccelerator)을 읽으므로 macOS 업데이트 후 표시되지 않거나 부정확해질 수 있습니다. 네트워크는 루프백을 제외한 모든 인터페이스의 합계입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
