import Foundation
import SwiftUI
import TUCore

/// Second time zone next to the menu bar icon, 24-hour, optional label: `NY 00:33`.
@MainActor
@Observable
public final class ClockModule: TUModule {
    public static let descriptor = ModuleDescriptor(
        id: "clock",
        displayName: "Clock",
        symbol: "clock"
    )

    static let defaultTimeZoneID = "America/New_York"

    @ObservationIgnored private let settings: ModuleSettings
    @ObservationIgnored private var ticker: Task<Void, Never>?
    private var now = Date()

    var timeZoneID: String {
        didSet { settings.set(timeZoneID, for: "timeZone") }
    }
    var showsLabel: Bool {
        didSet { settings.set(showsLabel, for: "showsLabel") }
    }
    /// Empty = derived from the city name.
    var customLabel: String {
        didSet { settings.set(customLabel, for: "label") }
    }

    public init(context: ModuleContext) {
        settings = context.settings
        timeZoneID = context.settings.value("timeZone", default: Self.defaultTimeZoneID)
        showsLabel = context.settings.value("showsLabel", default: true)
        customLabel = context.settings.value("label", default: "")
    }

    public func start() async throws {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                // Wake right after the next minute boundary.
                let seconds = Date().timeIntervalSinceReferenceDate
                let untilNextMinute = 60 - seconds.truncatingRemainder(dividingBy: 60) + 0.05
                try? await Task.sleep(for: .seconds(untilNextMinute))
            }
        }
    }

    public func stop() async {
        ticker?.cancel()
        ticker = nil
    }

    public var statusItemText: String? {
        let timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let label = customLabel.isEmpty ? Self.derivedLabel(for: timeZoneID) : customLabel
        return Self.format(now, timeZone: timeZone, label: showsLabel ? label : nil)
    }

    public func makeSettingsView() -> AnyView {
        AnyView(ClockSettingsView(module: self))
    }

    // MARK: - Formatting

    nonisolated static func format(_ date: Date, timeZone: TimeZone, label: String?) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        guard let label, !label.isEmpty else { return time }
        return "\(label) \(time)"
    }

    /// "America/New_York" → "NY", "Europe/London" → "LON", "Asia/Seoul" → "SEO".
    nonisolated static func derivedLabel(for timeZoneID: String) -> String {
        let city = (timeZoneID.split(separator: "/").last.map(String.init) ?? timeZoneID)
            .replacingOccurrences(of: "_", with: " ")
        let words = city.split(separator: " ")
        if words.count > 1 {
            return words.compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(city.prefix(3)).uppercased()
    }

    nonisolated static func cityName(for timeZoneID: String) -> String {
        (timeZoneID.split(separator: "/").last.map(String.init) ?? timeZoneID)
            .replacingOccurrences(of: "_", with: " ")
    }
}

private struct ClockSettingsView: View {
    @Bindable var module: ClockModule
    @State private var search = ""

    private var matchingZones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !search.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(search.replacingOccurrences(of: " ", with: "_")) }
    }

    var body: some View {
        Form {
            Section("표시") {
                LabeledContent("메뉴바 미리보기", value: module.statusItemText ?? "")
                Toggle("지역 라벨 표시", isOn: $module.showsLabel)
                if module.showsLabel {
                    TextField(
                        "라벨",
                        text: $module.customLabel,
                        prompt: Text(ClockModule.derivedLabel(for: module.timeZoneID))
                    )
                }
            }
            Section("시간대") {
                LabeledContent("현재", value: "\(ClockModule.cityName(for: module.timeZoneID)) (\(module.timeZoneID))")
                TextField("검색", text: $search, prompt: Text("도시 이름 (예: New York, Seoul)"))
                List(matchingZones, id: \.self, selection: Binding(
                    get: { module.timeZoneID },
                    set: { if let id = $0 { module.timeZoneID = id } }
                )) { id in
                    Text(id.replacingOccurrences(of: "_", with: " "))
                }
                .frame(height: 180)
            }
        }
        .formStyle(.grouped)
    }
}
