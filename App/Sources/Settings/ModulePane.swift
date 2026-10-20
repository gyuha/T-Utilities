import SwiftUI
import TUCore

struct ModulePane: View {
    let registry: ModuleRegistry
    let moduleID: String

    var body: some View {
        if let descriptor = registry.descriptor(for: moduleID) {
            Group {
                if let module = registry.active[moduleID] {
                    module.makeSettingsView()
                } else {
                    ContentUnavailableView(
                        "\(descriptor.displayName) 꺼짐",
                        systemImage: descriptor.symbol,
                        description: Text("모듈을 켜면 설정이 표시됩니다.")
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            // A pinned header instead of a second fixed-size Form: extra status rows must not raise the
            // pane's minimum height, or the content overflows above the window when it doesn't fit.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    ModuleToggleRow(registry: registry, descriptor: descriptor, showsHandle: false)
                    if let error = registry.startErrors[moduleID] {
                        Label("시작 실패: \(error)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                    if let status = registry.active[moduleID]?.status, let message = message(for: status) {
                        Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }
            .navigationTitle(descriptor.displayName)
        }
    }

    private func message(for status: ModuleStatus) -> String? {
        switch status {
        case .running: nil
        case .needsPermission(let permission): "\(permission.displayName) 권한이 필요합니다. 권한 페이지에서 허용하세요."
        case .degraded(let reason): reason
        case .error(let reason): reason
        }
    }
}
