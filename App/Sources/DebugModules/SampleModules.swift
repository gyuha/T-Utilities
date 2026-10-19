#if DEBUG
import Foundation
import KeyboardShortcuts
import SwiftUI
import TUCore
import TUUI

// Placeholder modules that exercise the shell (popover section, hotkey, settings, status item text,
// memory release). Debug builds only; removed once real modules exist.

extension KeyboardShortcuts.Name {
    static let sampleIncrement = Self("sample.increment")
}

@MainActor
@Observable
final class SampleCounterModule: TUModule {
    static let descriptor = ModuleDescriptor(
        id: "sample.counter",
        displayName: "Sample Counter",
        symbol: "number.circle",
        hasPopoverSection: true
    )

    private let settings: ModuleSettings
    var count = 0
    var step: Int {
        didSet { settings.set(step, for: "step") }
    }

    init(context: ModuleContext) {
        settings = context.settings
        step = context.settings.value("step", default: 1)
    }

    func start() async throws {}
    func stop() async {}

    var hotkeys: [HotkeyDefinition] {
        [HotkeyDefinition(name: .sampleIncrement, title: "카운터 증가") { [weak self] in self?.increment() }]
    }

    func increment() {
        count += step
    }

    func makePopoverSection() -> AnyView? {
        AnyView(SampleCounterSection(module: self))
    }

    func makeSettingsView() -> AnyView {
        AnyView(Form {
            Stepper("증가 단위: \(step)", value: Binding(get: { self.step }, set: { self.step = $0 }), in: 1...10)
        }.formStyle(.grouped))
    }
}

private struct SampleCounterSection: View {
    let module: SampleCounterModule

    var body: some View {
        Button(action: module.increment) {
            SectionRow(symbol: "number.circle", title: "Sample Counter") {
                Text("\(module.count)")
            }
        }
        .buttonStyle(.plain)
    }
}

/// Shows elapsed seconds next to the menu bar icon and holds a large buffer, so enabling/disabling it
/// makes memory release visible in `footprint`.
@MainActor
@Observable
final class SampleTickerModule: TUModule {
    static let descriptor = ModuleDescriptor(
        id: "sample.ticker",
        displayName: "Sample Ticker",
        symbol: "timer",
        enabledByDefault: false
    )

    private var seconds = 0
    private var ticker: Task<Void, Never>?
    @ObservationIgnored private var ballast: [UInt8] = []

    init(context: ModuleContext) {}

    func start() async throws {
        ballast = [UInt8](repeating: 1, count: 64 * 1024 * 1024)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.seconds += 1
            }
        }
    }

    func stop() async {
        ticker?.cancel()
        ticker = nil
        ballast = []
    }

    var statusItemText: String? { "T\(seconds)" }

    func makeSettingsView() -> AnyView {
        AnyView(Form {
            LabeledContent("경과", value: "\(seconds)초")
            LabeledContent("버퍼", value: "64 MB")
        }.formStyle(.grouped))
    }
}
#endif
