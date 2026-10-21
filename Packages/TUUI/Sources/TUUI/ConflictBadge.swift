import SwiftUI

/// Red warning symbol placed before a key combination that clashes with common macOS/app behavior.
/// Hovering shows a short explanation.
public struct ConflictBadge: View {
    let message: String
    @State private var isHovering = false

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .accessibilityLabel(message)
            .onHover { isHovering = $0 }
            .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
                    .padding(10)
            }
    }
}
