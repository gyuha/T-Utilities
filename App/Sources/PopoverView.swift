import SwiftUI
import TUCore

/// Main popover: a vertical stack of module sections in user order, followed by a footer.
struct PopoverView: View {
    let registry: ModuleRegistry
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
    }
}
