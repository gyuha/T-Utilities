import AppKit
import KeyboardShortcuts
import Testing
import TUCore
@testable import ModClipboard

// Uses uniquely named pasteboards so the user's general clipboard is never touched.
@MainActor
@Suite(.serialized)
struct PlainTextPasteTests {
    func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ModClipboardTests.\(UUID().uuidString)"))
    }

    func writeRichText(to pasteboard: NSPasteboard, plain: String) {
        pasteboard.clearContents()
        pasteboard.setString(plain, forType: .string)
        pasteboard.setString("<b>\(plain)</b>", forType: .html)
        pasteboard.setData(Data("{\\rtf1 \(plain)}".utf8), forType: .rtf)
    }

    @Test func PlainTextReplacementLeavesOnlyStringType() {
        let pasteboard = makePasteboard()
        writeRichText(to: pasteboard, plain: "hello")
        let snapshot = PlainTextPaste.replaceWithPlainText(on: pasteboard)
        #expect(snapshot != nil)
        let types = Set(pasteboard.types ?? [])
        #expect(types.contains(.string))
        #expect(!types.contains(.html) && !types.contains(.rtf))
        #expect(pasteboard.string(forType: .string) == "hello")
    }

    @Test func PlainTextNonTextClipboardIsNoOp() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(Data([1, 2, 3]), forType: .png)
        let before = pasteboard.changeCount
        #expect(PlainTextPaste.replaceWithPlainText(on: pasteboard) == nil)
        #expect(pasteboard.changeCount == before)
        #expect(pasteboard.types?.contains(.png) == true)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test func PlainTextRestoreBringsBackRichTypes() {
        let pasteboard = makePasteboard()
        writeRichText(to: pasteboard, plain: "hi")
        let snapshot = PlainTextPaste.replaceWithPlainText(on: pasteboard)!
        PlainTextPaste.restore(snapshot, on: pasteboard)
        let types = Set(pasteboard.types ?? [])
        #expect(types.isSuperset(of: [.string, .html, .rtf]))
    }

    @Test func PlainTextRestoreIsByteIdentical() {
        let pasteboard = makePasteboard()
        writeRichText(to: pasteboard, plain: "bytes")
        let originalHTML = pasteboard.data(forType: .html)
        let originalRTF = pasteboard.data(forType: .rtf)
        let snapshot = PlainTextPaste.replaceWithPlainText(on: pasteboard)!
        PlainTextPaste.restore(snapshot, on: pasteboard)
        #expect(pasteboard.data(forType: .html) == originalHTML)
        #expect(pasteboard.data(forType: .rtf) == originalRTF)
        #expect(pasteboard.string(forType: .string) == "bytes")
    }

    @Test func hotkeysIncludePlainTextPasteDistinctFromToggle() {
        let context = ModuleContext(
            settings: ModuleSettings(defaults: UserDefaults(suiteName: "ModClipboardTests.\(UUID().uuidString)")!, moduleID: "clipboard"),
            log: ModuleLog(category: "test"),
            popover: PopoverControl()
        )
        let module = ClipboardModule(context: context, storageURL: FileManager.default.temporaryDirectory)
        let hotkeys = module.hotkeys
        #expect(hotkeys.contains { $0.name == .clipboardToggle })
        let plain = hotkeys.filter { $0.name == .clipboardPlainTextPaste }
        #expect(plain.count == 1)
        #expect(Set(hotkeys.map(\.name.rawValue)).count == hotkeys.count)
        #expect(KeyboardShortcuts.Name.clipboardPlainTextPaste.defaultShortcut != nil)
        #expect(KeyboardShortcuts.Name.clipboardPlainTextPaste.defaultShortcut != KeyboardShortcuts.Name.clipboardToggle.defaultShortcut)
    }
}
