import SwiftUI
import TUCore
import TUUI

enum SettingsPage: Hashable {
    case general
    case popover
    case permissions
    case module(String)
}

struct SettingsView: View {
    let registry: ModuleRegistry
    let permissions: PermissionCenter
    @State private var selection: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("일반", systemImage: "gearshape").tag(SettingsPage.general)
                Label("팝오버", systemImage: "rectangle.stack").tag(SettingsPage.popover)
                Label("권한", systemImage: "lock.shield").tag(SettingsPage.permissions)
                Section("모듈") {
                    ForEach(registry.descriptors) { descriptor in
                        HStack {
                            Label(descriptor.displayName, systemImage: descriptor.symbol)
                            Spacer()
                            StatusBadge(
                                enabled: registry.isEnabled(descriptor.id),
                                status: registry.active[descriptor.id]?.status,
                                startFailed: registry.startErrors[descriptor.id] != nil
                            )
                        }
                        .tag(SettingsPage.module(descriptor.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralPane(registry: registry)
            case .popover:
                PopoverPane(registry: registry)
            case .permissions:
                PermissionsPane(registry: registry, permissions: permissions)
            case .module(let id):
                ModulePane(registry: registry, moduleID: id)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}
