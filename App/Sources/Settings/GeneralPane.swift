import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import TUCore

struct GeneralPane: View {
    let registry: ModuleRegistry
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("단축키") {
                let hotkeys = registry.activeModules.flatMap { module in
                    module.hotkeys.map { (module: type(of: module).descriptor, hotkey: $0) }
                }
                if hotkeys.isEmpty {
                    Text("활성 모듈에 단축키가 없습니다").foregroundStyle(.secondary)
                }
                ForEach(hotkeys, id: \.hotkey.name.rawValue) { item in
                    LabeledContent {
                        KeyboardShortcuts.Recorder(for: item.hotkey.name)
                    } label: {
                        Label("\(item.module.displayName) · \(item.hotkey.title)", systemImage: item.module.symbol)
                    }
                }
            }

            let conflicts = runningConflicts
            if !conflicts.isEmpty {
                Section("충돌하는 앱") {
                    ForEach(conflicts, id: \.app) { conflict in
                        Label(
                            "\(conflict.app)이(가) 실행 중입니다. \(conflict.module) 모듈과 동시에 사용하면 기능이 중복 적용됩니다.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("일반")
    }

    private var runningConflicts: [(app: String, module: String)] {
        let running = NSWorkspace.shared.runningApplications
        return registry.descriptors
            .filter { registry.isEnabled($0.id) }
            .flatMap { descriptor in
                running
                    .filter { app in descriptor.conflictingBundleIDs.contains(app.bundleIdentifier ?? "") }
                    .map { (app: $0.localizedName ?? $0.bundleIdentifier ?? "?", module: descriptor.displayName) }
            }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
