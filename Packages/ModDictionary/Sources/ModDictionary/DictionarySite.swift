import Foundation

/// Web dictionaries the panel can show. Raw value is what gets stored in the module settings.
enum DictionarySite: String, CaseIterable, Identifiable {
    case naver
    case daum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .naver: "네이버 사전"
        case .daum: "다음 사전"
        }
    }

    /// Mobile-sized pages that fit the small panel (same pages allkdic uses).
    var url: URL {
        switch self {
        case .naver: URL(string: "https://en.dict.naver.com/#/mini/main")!
        case .daum: URL(string: "https://small.dic.daum.net/top/search.do?dic=all")!
        }
    }

    /// Digit pressed together with ⌘ inside the panel.
    var shortcutKey: String {
        switch self {
        case .naver: "1"
        case .daum: "2"
        }
    }

    init?(shortcutKey: String) {
        guard let site = Self.allCases.first(where: { $0.shortcutKey == shortcutKey }) else { return nil }
        self = site
    }
}
