import SwiftUI
import TUCore

/// Sidebar/status dot: green running, yellow needs attention, gray off, red error.
public struct StatusBadge: View {
    public enum State: Equatable {
        case off
        case running
        case attention
        case error
    }

    let state: State

    public init(_ state: State) {
        self.state = state
    }

    public init(enabled: Bool, status: ModuleStatus?, startFailed: Bool) {
        switch (enabled, status) {
        case (false, _): state = .off
        case (true, _) where startFailed: state = .error
        case (true, .error?): state = .error
        case (true, .needsPermission?), (true, .degraded?): state = .attention
        case (true, .running?): state = .running
        case (true, nil): state = .off
        }
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch state {
        case .off: .gray.opacity(0.5)
        case .running: .green
        case .attention: .yellow
        case .error: .red
        }
    }

    private var label: String {
        switch state {
        case .off: "꺼짐"
        case .running: "동작 중"
        case .attention: "확인 필요"
        case .error: "오류"
        }
    }
}
