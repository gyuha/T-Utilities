import AppKit
import SwiftUI
import TUCore
import TUUI

// Mouse features adapted from LinearMouse (MIT, © LinearMouse) — https://github.com/linearmouse/linearmouse

/// Pointer speed/acceleration, side-button actions, wheel corrections and Logitech HID++ battery.
@MainActor
@Observable
public final class MouseModule: TUModule {
    public static let descriptor = ModuleDescriptor(
        id: "mouse",
        displayName: "Mouse",
        symbol: "computermouse",
        requiredPermissions: [.accessibility],
        hasPopoverSection: true,
        // An event-tap bug can break input, so the user opts in.
        enabledByDefault: false,
        conflictingBundleIDs: ["com.lujjjh.LinearMouse"]
    )

    /// HID++ battery poll; devices also push battery events in between.
    static let batteryPollInterval: Duration = .seconds(300)
    /// Defaults carried over from the user's LinearMouse config.
    static let defaultSpeed = 0.08
    static let defaultAcceleration = 0.9

    @ObservationIgnored private let settings: ModuleSettings
    @ObservationIgnored private let pointer = PointerTuner()
    @ObservationIgnored private let eventTap = MouseEventTap()
    @ObservationIgnored private let battery = LogitechBattery()
    @ObservationIgnored private var batteryPoller: Task<Void, Never>?
    @ObservationIgnored private var permissionWaiter: Task<Void, Never>?
    @ObservationIgnored private var reapplyTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshingBattery = false

    private(set) var batteries: [MouseBatteryInfo] = []
    private(set) var tapInstalled = false

    var pointerEnabled: Bool {
        didSet { settings.set(pointerEnabled, for: "pointerEnabled"); applyPointer() }
    }
    var speed: Double {
        didSet { settings.set(speed, for: "speed"); applyPointer() }
    }
    var acceleration: Double {
        didSet { settings.set(acceleration, for: "acceleration"); applyPointer() }
    }
    var backButtonAction: MouseAction {
        didSet { settings.set(backButtonAction.rawValue, for: "button3"); applyEventTapConfig() }
    }
    var forwardButtonAction: MouseAction {
        didSet { settings.set(forwardButtonAction.rawValue, for: "button4"); applyEventTapConfig() }
    }
    var reverseScroll: Bool {
        didSet { settings.set(reverseScroll, for: "reverseScroll"); applyEventTapConfig() }
    }
    /// 0 = macOS default (accelerated).
    var scrollLines: Int {
        didSet { settings.set(scrollLines, for: "scrollLines"); applyEventTapConfig() }
    }

    public init(context: ModuleContext) {
        settings = context.settings
        pointerEnabled = context.settings.value("pointerEnabled", default: true)
        speed = context.settings.value("speed", default: Self.defaultSpeed)
        acceleration = context.settings.value("acceleration", default: Self.defaultAcceleration)
        backButtonAction = MouseAction(rawValue: context.settings.value("button3", default: "")) ?? .showDesktop
        forwardButtonAction = MouseAction(rawValue: context.settings.value("button4", default: "")) ?? .missionControl
        reverseScroll = context.settings.value("reverseScroll", default: false)
        scrollLines = context.settings.value("scrollLines", default: 0)
    }

    public func start() async throws {
        applyPointer()
        pointer.watchDevices { [weak self] in self?.devicesChanged() }

        applyEventTapConfig()
        installEventTap()

        battery.onChange = { [weak self] in self?.batteries = $0 }
        battery.start()
        batteryPoller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshBattery()
                try? await Task.sleep(for: Self.batteryPollInterval)
            }
        }
    }

    public func stop() async {
        batteryPoller?.cancel()
        permissionWaiter?.cancel()
        reapplyTask?.cancel()
        batteryPoller = nil
        permissionWaiter = nil
        reapplyTask = nil
        eventTap.uninstall()
        tapInstalled = false
        pointer.stopWatching()
        pointer.restore()
        battery.onChange = nil
        battery.stop()
        batteries = []
    }

    public var status: ModuleStatus {
        tapInstalled ? .running : .needsPermission(.accessibility)
    }

    // MARK: - Pointer

    private func applyPointer() {
        if pointerEnabled {
            pointer.apply(.init(speed: speed, acceleration: acceleration))
        } else {
            pointer.restore()
        }
    }

    /// New or re-enumerated mice (receiver replugged, wake from sleep) start with system values.
    private func devicesChanged() {
        reapplyTask?.cancel()
        reapplyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            applyPointer()
            await refreshBattery()
        }
    }

    // MARK: - Event tap

    private func applyEventTapConfig() {
        eventTap.buttonActions = [3: backButtonAction, 4: forwardButtonAction]
        eventTap.scroll = ScrollOptions(reverse: reverseScroll, lines: scrollLines)
    }

    /// The tap needs Accessibility; wait for the grant instead of asking on every launch.
    private func installEventTap() {
        tapInstalled = eventTap.install()
        guard !tapInstalled else { return }
        permissionWaiter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                guard Permission.accessibility.isGranted else { continue }
                tapInstalled = eventTap.install()
                if tapInstalled { return }
            }
        }
    }

    // MARK: - Battery

    func refreshBattery() async {
        guard !isRefreshingBattery else { return }
        isRefreshingBattery = true
        defer { isRefreshingBattery = false }
        await battery.refresh()
    }

    // MARK: - Shell integration

    public func makePopoverSection() -> AnyView? {
        AnyView(MouseSectionView(module: self))
    }

    public func makeSettingsView() -> AnyView {
        AnyView(MouseSettingsView(module: self))
    }

    nonisolated static func shortName(_ name: String) -> String {
        // "G304 Lightspeed Wireless Gaming Mouse" → "G304"
        name.split(separator: " ").first.map(String.init) ?? name
    }

    nonisolated static func batterySymbol(_ reading: BatteryReading) -> String {
        if reading.chargeState == .charging { return "battery.100percent.bolt" }
        switch reading.level ?? 0 {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

private struct MouseSectionView: View {
    let module: MouseModule

    var body: some View {
        if module.batteries.isEmpty {
            SectionRow(symbol: "computermouse", title: "Mouse") {
                Text("배터리 정보 없음")
            }
        }
        ForEach(module.batteries) { info in
            SectionRow(symbol: "computermouse", title: MouseModule.shortName(info.name)) {
                HStack(spacing: 4) {
                    Image(systemName: MouseModule.batterySymbol(info.reading))
                        .foregroundStyle((info.reading.level ?? 100) <= 15 ? .red : .secondary)
                    Text(info.reading.level.map { "\($0)%" } ?? "—")
                }
            }
            .help(info.name)
        }
    }
}

private struct MouseSettingsView: View {
    @Bindable var module: MouseModule

    var body: some View {
        Form {
            Section("배터리") {
                if module.batteries.isEmpty {
                    Text("Logitech HID++ 장치를 찾지 못했습니다 (마우스가 잠들어 있으면 움직인 뒤 새로 고침)")
                        .foregroundStyle(.secondary)
                }
                ForEach(module.batteries) { info in
                    LabeledContent(info.name) {
                        HStack(spacing: 4) {
                            Image(systemName: MouseModule.batterySymbol(info.reading))
                                .foregroundStyle((info.reading.level ?? 100) <= 15 ? .red : .secondary)
                            Text(info.reading.level.map { "\($0)%" } ?? "—").monospacedDigit()
                        }
                    }
                }
                Button("새로 고침") { Task { await module.refreshBattery() } }
            }

            if !module.tapInstalled {
                Section {
                    LabeledContent {
                        Button("허용하기…") { Permission.accessibility.request() }
                    } label: {
                        Label("버튼·스크롤 기능에는 손쉬운 사용 권한이 필요합니다", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Toggle("포인터 설정 적용", isOn: $module.pointerEnabled)
                LabeledContent("속도") {
                    HStack {
                        Slider(value: $module.speed, in: 0...1)
                        Text(module.speed, format: .number.precision(.fractionLength(2))).monospacedDigit().frame(width: 36)
                    }
                }
                .disabled(!module.pointerEnabled)
                LabeledContent("가속") {
                    HStack {
                        Slider(value: $module.acceleration, in: 0...3)
                        Text(module.acceleration, format: .number.precision(.fractionLength(2))).monospacedDigit().frame(width: 36)
                    }
                }
                .disabled(!module.pointerEnabled)
                Button("LinearMouse 값으로 되돌리기 (속도 0.08 · 가속 0.9)") {
                    module.speed = MouseModule.defaultSpeed
                    module.acceleration = MouseModule.defaultAcceleration
                }
            } header: {
                Text("포인터")
            } footer: {
                Text("연결된 모든 마우스에 적용됩니다(트랙패드 제외). 모듈을 끄거나 앱을 종료하면 원래 값으로 돌아갑니다. 시스템 설정에서 추적 속도를 바꾸면 그 값이 우선합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("측면 버튼") {
                Picker("뒤로 버튼 (3)", selection: $module.backButtonAction) {
                    ForEach(MouseAction.allCases) { Text($0.title).tag($0) }
                }
                Picker("앞으로 버튼 (4)", selection: $module.forwardButtonAction) {
                    ForEach(MouseAction.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("스크롤 방향 반전", isOn: $module.reverseScroll)
                Picker("휠 한 칸당", selection: $module.scrollLines) {
                    Text("macOS 기본 (가속)").tag(0)
                    ForEach([1, 2, 3, 4, 5, 6, 8, 10], id: \.self) { Text("\($0)줄").tag($0) }
                }
            } header: {
                Text("스크롤 보정")
            } footer: {
                Text("마우스 휠에만 적용되고 트랙패드에는 적용되지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }
}
