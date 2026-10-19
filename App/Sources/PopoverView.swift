import SwiftUI
import TUCore

/// Main popover: a vertical stack of module sections in user order, followed by a footer.
struct PopoverView: View {
    let registry: ModuleRegistry
    let updater: Updater
    let openSettings: () -> Void

    var body: some View {
        let sections = registry.popoverOrder.compactMap { registry.active[$0.id]?.makePopoverSection() }

        VStack(spacing: 0) {
            if sections.isEmpty {
                Text("팝오버에 표시할 모듈이 없습니다")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ForEach(sections.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    sections[index]
                }
            }
            Divider()
            HStack {
                Button("설정", systemImage: "gearshape", action: openSettings)
                    .buttonStyle(.borderless)
                Spacer()
                switch updater.state {
                case .available(let release):
                    Button("업데이트 v\(release.version)", systemImage: "arrow.down.circle", action: updater.install)
                        .buttonStyle(.borderless)
                        .help("다운로드 후 설치하고 다시 실행합니다")
                case .installing:
                    ProgressView().controlSize(.small)
                    Text("업데이트 설치 중…").font(.caption).foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
    }
}
