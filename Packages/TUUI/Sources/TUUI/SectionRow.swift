import SwiftUI

/// Standard one-line popover row: icon · title · trailing value · optional chevron.
public struct SectionRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let showsChevron: Bool
    let trailing: Trailing

    public init(symbol: String, title: String, showsChevron: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.showsChevron = showsChevron
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 8)
            trailing
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

public extension SectionRow where Trailing == EmptyView {
    init(symbol: String, title: String, showsChevron: Bool = false) {
        self.init(symbol: symbol, title: title, showsChevron: showsChevron) { EmptyView() }
    }
}
