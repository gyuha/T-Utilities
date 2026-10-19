import ModAwake
import ModClipboard
import ModClock
import TUCore

/// Every module the app ships with, in default order. Adding a module = adding its type here.
@MainActor
enum AppModules {
    static let all: [any TUModule.Type] = [
        AwakeModule.self,
        ClipboardModule.self,
        ClockModule.self,
    ]
}
