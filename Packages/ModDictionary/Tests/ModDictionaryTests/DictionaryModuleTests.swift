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
}
