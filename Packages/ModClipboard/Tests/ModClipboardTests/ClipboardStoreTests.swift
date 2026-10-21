import AppKit
import Foundation
import Testing
import TUCore
@testable import ModClipboard

// These tests never touch NSPasteboard.general writes (copyToClipboard / clearAll) so the user's clipboard is safe.
@MainActor
@Suite(.serialized)
struct ClipboardStoreTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModClipboardTests-\(UUID().uuidString)", isDirectory: true)
    }

    func makeStore() -> ClipboardStore {
        ClipboardStore(persistence: PersistenceManager(baseURL: directory))
    }

    func text(_ string: String) -> ClipboardCapture {
        ClipboardCapture(content: .text(string))
    }

    @Test func newestCaptureIsOnTopAndDuplicatesArePromoted() {
        let store = makeStore()
        store.add(text("a"))
        store.add(text("b"))
        store.add(text("a"))
        #expect(store.items.compactMap(\.text) == ["a", "b"])
    }

    @Test func historyIsCappedAtMaxItems() {
        let store = makeStore()
        for index in 0..<(ClipboardStore.maxItems + 5) {
            store.add(text("item \(index)"))
        }
        #expect(store.items.count == ClipboardStore.maxItems)
        #expect(store.items.first?.text == "item \(ClipboardStore.maxItems + 4)")
    }

    @Test func searchFiltersCaseInsensitivelyAndQuickSlotsFollowFilter() {
        let store = makeStore()
        ["Apple", "banana", "apricot", "cherry"].forEach { store.add(text($0)) }
        store.searchText = "AP"
        #expect(store.filteredItems.compactMap(\.text) == ["apricot", "Apple"])
        #expect(store.quickSlotItem(1)?.text == "apricot")
        #expect(store.quickSlotItem(2)?.text == "Apple")
        #expect(store.quickSlotItem(3) == nil)
    }

    @Test func quickSlotZeroIsTheTenthItem() {
        let store = makeStore()
        (1...10).reversed().forEach { store.add(text("n\($0)")) }
        #expect(store.quickSlotItem(1)?.text == "n1")
        #expect(store.quickSlotItem(0)?.text == "n10")
    }

    @Test func selectionMovesWithinBounds() {
        let store = makeStore()
        ["x", "y"].forEach { store.add(text($0)) }
        store.prepareForPresentation()
        #expect(store.selectedIndex == 0)
        store.moveSelection(5)
        #expect(store.selectedIndex == 1)
        store.moveSelection(-5)
        #expect(store.selectedIndex == 0)
    }

    @Test func historyPersistsAcrossStores() {
        let store = makeStore()
        store.add(text("persisted"))
        store.persistence.flush()

        let reloaded = makeStore()
        #expect(reloaded.items.compactMap(\.text) == ["persisted"])
    }

    @Test func imagesAreStoredAndPrunedWhenEvicted() throws {
        let store = makeStore()
        let raw = try #require(Self.pngData())
        let capture = try #require(ImageProcessor.prepare(ClipboardCapture(content: .imageRaw(raw))))
        store.add(capture)
        store.persistence.flush()

        let fileName = try #require(store.items.first?.imageFileName)
        #expect(FileManager.default.fileExists(atPath: store.persistence.imageFileURL(fileName).path))
        #expect(store.imageCache.thumbnail(for: fileName) != nil)

        for index in 0..<ClipboardStore.maxItems {
            store.add(text("evict \(index)"))
        }
        store.persistence.flush()
        #expect(!FileManager.default.fileExists(atPath: store.persistence.imageFileURL(fileName).path))
    }

    static func pngData() -> Data? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        return rep?.representation(using: .png, properties: [:])
    }
}

@MainActor
struct ClipboardModuleTests {
    @Test func stopReleasesStoreAndMonitor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModClipboardTests-\(UUID().uuidString)", isDirectory: true)
        let suite = "ModClipboardTests.\(UUID().uuidString)"
        let context = ModuleContext(
            settings: ModuleSettings(defaults: UserDefaults(suiteName: suite)!, moduleID: "clipboard"),
            log: ModuleLog(category: "test"),
            popover: PopoverControl()
        )
        var module: ClipboardModule? = ClipboardModule(context: context, storageURL: directory)
        try await module?.start()
        #expect(module?.makePopoverSection() != nil)

        await module?.stop()
        #expect(module?.makePopoverSection() == nil)
        weak var released = module
        module = nil
        #expect(released == nil)
    }

    @Test func autoPasteSettingPersistsAndDefaultsOff() {
        let suite = "ModClipboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        func makeModule() -> ClipboardModule {
            let context = ModuleContext(
                settings: ModuleSettings(defaults: defaults, moduleID: "clipboard"),
                log: ModuleLog(category: "test"),
                popover: PopoverControl()
            )
            return ClipboardModule(context: context, storageURL: FileManager.default.temporaryDirectory)
        }
        let first = makeModule()
        #expect(first.autoPaste == false)
        first.autoPaste = true
        #expect(makeModule().autoPaste == true)
    }
}
