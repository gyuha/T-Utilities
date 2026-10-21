import SwiftUI
import TUCore

/// Main popover: a vertical stack of module sections in user order, followed by a footer.
struct PopoverView: View {
    let registry: ModuleRegistry
    let updater: Updater
    let openSettings: () -> Void

    @AppStorage(PopoverSize.widthKey) private var width = Double(PopoverSize.defaultWidth)
    @AppStorage(PopoverSize.listHeightKey) private var listHeight = Double(PopoverSize.defaultListHeight)

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
                    Button(action: updater.confirmAndInstall) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("New update")
                            Text("v\(release.version)").monospacedDigit()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.yellow, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("새 버전으로 업데이트")
                case .installing:
                    ProgressView().controlSize(.small)
                    Text("업데이트 설치 중…").font(.caption).foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottomTrailing) {
                PopoverResizeGrip(width: $width, listHeight: $listHeight)
                    .frame(width: 28, height: 28)
                    .help("끌어서 창 크기 조절")
            }
        }
        .frame(width: width)
    }
}
