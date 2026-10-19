import SwiftUI
import TUCore

struct ModulePane: View {
    let registry: ModuleRegistry
    let moduleID: String

    var body: some View {
        if let descriptor = registry.descriptor(for: moduleID) {
            VStack(spacing: 0) {
                Form {
                    Section {
                        ModuleToggleRow(registry: registry, descriptor: descriptor, showsHandle: false)
                        if let error = registry.startErrors[moduleID] {
                            Label("시작 실패: \(error)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        }
                        if let status = registry.active[moduleID]?.status, let message = message(for: status) {
                            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)

                if let module = registry.active[moduleID] {
                    module.makeSettingsView()
                } else {
                    ContentUnavailableView(
                        "\(descriptor.displayName) 꺼짐",
                        systemImage: descriptor.symbol,
                        description: Text("모듈을 켜면 설정이 표시됩니다.")
                    )
                }
                Spacer(minLength: 0)
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
