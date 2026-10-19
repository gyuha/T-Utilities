import AppKit

/// NSMenuItem that runs a closure, so modules can build menus without @objc targets.
@MainActor
public final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    public init(_ title: String, isChecked: Bool = false, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = isChecked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
