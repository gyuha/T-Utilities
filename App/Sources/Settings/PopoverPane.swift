import SwiftUI
import TUCore

/// Enable/disable every module and reorder the popover sections.
struct PopoverPane: View {
    let registry: ModuleRegistry

    var body: some View {
        Form {
            Section {
                ForEach(registry.popoverOrder) { descriptor in
                    ModuleToggleRow(registry: registry, descriptor: descriptor, showsHandle: true)
                }
                .onMove { source, destination in
                    registry.movePopoverItems(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("팝오버 섹션")
            } footer: {
                Text("드래그해서 순서를 바꿉니다. 끈 모듈은 중지되고 메모리에서 해제됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            let others = registry.order.compactMap(registry.descriptor(for:)).filter { !$0.hasPopoverSection }
            if !others.isEmpty {
                Section("팝오버 섹션 없음") {
                    ForEach(others) { descriptor in
                        ModuleToggleRow(registry: registry, descriptor: descriptor, showsHandle: false)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("팝오버")
    }
}

struct ModuleToggleRow: View {
    let registry: ModuleRegistry
    let descriptor: ModuleDescriptor
    let showsHandle: Bool

    var body: some View {
        HStack {
            if showsHandle {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            }
            Label(descriptor.displayName, systemImage: descriptor.symbol)
            Spacer()
            Toggle("", isOn: Binding(
                get: { registry.isEnabled(descriptor.id) },
                set: { enabled in Task { await registry.setEnabled(enabled, for: descriptor.id) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}
