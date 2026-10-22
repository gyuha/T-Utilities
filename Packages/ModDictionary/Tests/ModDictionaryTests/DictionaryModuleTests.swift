import AppKit
import KeyboardShortcuts
import Testing
@testable import ModDictionary

@MainActor
struct DictionaryModuleTests {
    @Test func eachSiteHasItsURL() {
        #expect(DictionarySite.naver.url.absoluteString == "https://en.dict.naver.com/#/mini/main")
        #expect(DictionarySite.daum.url.absoluteString == "https://small.dic.daum.net/top/search.do?dic=all")
    }

    @Test func shortcutKeysMapToSites() {
        #expect(DictionarySite(shortcutKey: "1") == .naver)
        #expect(DictionarySite(shortcutKey: "2") == .daum)
        #expect(DictionarySite(shortcutKey: "3") == nil)
    }

    @Test func defaultHotkeyIsFlaggedAsConflict() {
        let shortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.option, .command])
        #expect(DictionaryModule.hotkeyConflicts[shortcut] != nil)
        #expect(KeyboardShortcuts.Name.dictionaryToggle.initialShortcut == shortcut)
    }

    @Test func panelFrameKeepsPlaceRelativeToScreen() {
        let area = NSRect(x: 0, y: 0, width: 1440, height: 870)
        let frame = DictionaryPanelController.frame(size: NSSize(width: 500, height: 600), centerOffset: -100, topGap: 30, in: area)
        #expect(frame == NSRect(x: 370, y: 240, width: 500, height: 600))
        let other = NSRect(x: 1440, y: 0, width: 1920, height: 1050)
        #expect(DictionaryPanelController.frame(size: frame.size, centerOffset: -100, topGap: 30, in: other).midX == other.midX - 100)
    }

    @Test func panelFrameStaysOnSmallerScreen() {
        let area = NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = DictionaryPanelController.frame(size: NSSize(width: 700, height: 900), centerOffset: 300, topGap: 0, in: area)
        #expect(frame == NSRect(x: 100, y: 0, width: 700, height: 600))
    }
}
