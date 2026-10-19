import AppKit
import KeyboardShortcuts
import SwiftUI
import TUCore

// Window actions adapted from Rectangle (MIT, © Ryan Hanson; based on Spectacle © Eric Czarny)
// https://github.com/rxhanson/Rectangle — only Maximize and Next/Previous Display, with Rectangle's default shortcuts.

extension KeyboardShortcuts.Name {
    static let windowMaximize = Self("windows.maximize", initial: .init(.return, modifiers: [.control, .option]))
    static let windowNextDisplay = Self("windows.nextDisplay", initial: .init(.rightArrow, modifiers: [.control, .option, .command]))
    static let windowPreviousDisplay = Self("windows.previousDisplay", initial: .init(.leftArrow, modifiers: [.control, .option, .command]))
}

@MainActor
@Observable
public final class WindowsModule: TUModule {
    public static let descriptor = ModuleDescriptor(
        id: "windows",
        displayName: "Windows",
        symbol: "macwindow",
        requiredPermissions: [.accessibility],
        conflictingBundleIDs: ["com.knollsoft.Rectangle"]
    )

    public init(context: ModuleContext) {}

    public func start() async throws {}

    public func stop() async {}

    public var status: ModuleStatus {
        Permission.accessibility.isGranted ? .running : .needsPermission(.accessibility)
    }

    public var hotkeys: [HotkeyDefinition] {
        [
            HotkeyDefinition(name: .windowMaximize, title: "최대화") { Self.perform(.maximize) },
            HotkeyDefinition(name: .windowNextDisplay, title: "다음 디스플레이") { Self.perform(.nextDisplay) },
            HotkeyDefinition(name: .windowPreviousDisplay, title: "이전 디스플레이") { Self.perform(.previousDisplay) },
        ]
    }

    public func makeSettingsView() -> AnyView {
        AnyView(WindowsSettingsView())
    }

    // MARK: - Actions

    static func perform(_ action: WindowLayout.Action) {
        guard Permission.accessibility.isGranted else {
            Permission.accessibility.request()
            return
        }
        guard let window = AXWindow.frontmost(), !window.isSheet,
              let axFrame = window.frame,
              let primaryMaxY = NSScreen.screens.first?.frame.maxY else {
            NSSound.beep()
            return
        }
        let screens = NSScreen.screens.map { WindowLayout.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let current = WindowLayout.flipped(axFrame, primaryScreenMaxY: primaryMaxY)
        guard var target = WindowLayout.target(for: action, window: current, screens: screens) else {
            NSSound.beep()
            return
        }

        // Fixed-size windows can only be moved: keep their size, centered in the target area.
        if !window.isResizable {
            target = CGRect(
                x: target.midX - current.width / 2, y: target.midY - current.height / 2,
                width: current.width, height: current.height
            )
        }
        window.setFrame(WindowLayout.flipped(target, primaryScreenMaxY: primaryMaxY))

        // Windows with a minimum size may refuse the target and end up partly off-screen.
        guard let destination = WindowLayout.screenContaining(target, in: screens),
              let placed = window.frame else { return }
        let placedCocoa = WindowLayout.flipped(placed, primaryScreenMaxY: primaryMaxY)
        let fitted = WindowLayout.constrained(placedCocoa, to: destination.visibleFrame)
        if fitted.origin != placedCocoa.origin {
            window.set(position: WindowLayout.flipped(fitted, primaryScreenMaxY: primaryMaxY).origin)
        }
    }
}

private struct WindowsSettingsView: View {
    @State private var granted = Permission.accessibility.isGranted

    var body: some View {
        Form {
            Section {
                LabeledContent("최대화", value: "⌃⌥↩")
                LabeledContent("다음 디스플레이", value: "⌃⌥⌘→")
                LabeledContent("이전 디스플레이", value: "⌃⌥⌘←")
            } header: {
                Text("기본 단축키")
            } footer: {
                Text("단축키는 설정 → 일반에서 바꿀 수 있습니다. Rectangle이 실행 중이면 같은 단축키가 충돌하니 종료하세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !granted {
                Section {
                    LabeledContent {
                        Button("허용하기…") { Permission.accessibility.request() }
                    } label: {
                        Label("창을 옮기려면 손쉬운 사용 권한이 필요합니다", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                granted = Permission.accessibility.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
