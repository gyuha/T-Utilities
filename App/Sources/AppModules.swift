import ModClipboard
import TUCore

/// Every module the app ships with, in default order. Adding a module = adding its type here.
@MainActor
enum AppModules {
    static var all: [any TUModule.Type] {
        var modules: [any TUModule.Type] = [ClipboardModule.self]
        #if DEBUG
        modules += [SampleCounterModule.self, SampleTickerModule.self]
        #endif
        return modules
    }
}
