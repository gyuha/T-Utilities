import AppKit
import KeyboardShortcuts
import SwiftUI
import TUCore

// Adapted from CopyNinja (MIT, © 2026 Dawoon Yi / MelissaSoft) — https://github.com/dwyi84/CopyNinja

extension KeyboardShortcuts.Name {
    static let clipboardToggle = Self("clipboard.toggle", initial: .init(.v, modifiers: [.command, .shift]))
}

/// Clipboard history: captures text/images, search, quick slots (⌘1~0), OCR, Quick Look.
@MainActor
@Observable
public final class ClipboardModule: TUModule {
    public static let descriptor = ModuleDescriptor(
        id: "clipboard",
        displayName: "Clipboard",
        symbol: "doc.on.clipboard",
        hasPopoverSection: true,
        conflictingBundleIDs: ["com.melissasoft.CopyNinja"]
    )

    /// ANSI key codes for the top-row digits, mapped to quick slot numbers.
    private static let quickSlotKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0
    ]

    @ObservationIgnored private let popover: PopoverControl
    @ObservationIgnored private let storageURL: URL
    @ObservationIgnored private var store: ClipboardStore?
    @ObservationIgnored private var monitor: ClipboardMonitor?

    public required convenience init(context: ModuleContext) {
        self.init(context: context, storageURL: PersistenceManager.defaultBaseURL)
    }

    init(context: ModuleContext, storageURL: URL) {
        popover = context.popover
        self.storageURL = storageURL
    }

    public func start() async throws {
        let store = ClipboardStore(persistence: PersistenceManager(baseURL: storageURL))
        let monitor = ClipboardMonitor { [weak store] capture in
            store?.add(capture)
        }
        store.willWriteToClipboard = { [weak monitor] in
            monitor?.suppressNextChange()
        }
        store.onDismiss = { [popover] in
            popover.close()
        }
        monitor.start()
        self.store = store
        self.monitor = monitor
    }

    public func stop() async {
        monitor?.stop()
        monitor = nil
        store = nil
    }

    public var hotkeys: [HotkeyDefinition] {
        [HotkeyDefinition(name: .clipboardToggle, title: "클립보드 열기/닫기") { [popover] in popover.toggle() }]
    }

    public func makePopoverSection() -> AnyView? {
        guard let store else { return nil }
        return AnyView(ClipboardSectionView(store: store) { [popover] in popover.close() })
    }

    public func makeSettingsView() -> AnyView {
        guard let store else { return AnyView(EmptyView()) }
        return AnyView(ClipboardSettingsView(store: store))
    }

    public func popoverWillShow() {
        store?.prepareForPresentation()
    }

    // MARK: - Keyboard navigation

    public func handlePopoverKeyDown(_ event: NSEvent) -> Bool {
        guard let store else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        if keyCode == 53 { // Esc — dismiss Quick Look first; otherwise let the shell close the popover
            guard store.quickLookItem != nil else { return false }
            store.dismissQuickLook()
            return true
        }

        if flags.contains(.command) {
            if event.charactersIgnoringModifiers == "k" { // ⌘K
                store.clearAll()
                return true
            }
            if keyCode == 117 && flags.contains(.shift) { // ⌘⇧ForwardDelete
                store.clearAll()
                return true
            }
            if let slot = Self.quickSlotKeyCodes[keyCode] { // ⌘1~0 / ⌘⇧1~0
                if let item = store.quickSlotItem(slot) {
                    if flags.contains(.shift) {
                        store.performOCRCopy(for: item)
                    } else {
                        store.copyToClipboard(item)
                        popover.close()
                    }
                }
                return true
            }
            return false
        }
        if flags.contains(.option) || flags.contains(.control) {
            return false
        }

        switch keyCode {
        case 126: // ↑
            store.moveSelection(-1)
            return true
        case 125: // ↓
            store.moveSelection(1)
            return true
        case 36: // Return
            guard let item = store.selectedItem ?? store.filteredItems.first else { return true }
            if flags.contains(.shift) {
                store.performOCRCopy(for: item)
            } else {
                store.copyToClipboard(item)
                popover.close()
            }
            return true
        case 49: // Space — Quick Look while nothing is being typed
            guard store.searchText.isEmpty, store.selectedItem != nil else { return false }
            store.toggleQuickLook()
            return true
        default:
            return false
        }
    }
}

private struct ClipboardSettingsView: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        Form {
            Section("히스토리") {
                LabeledContent("저장된 항목", value: "\(store.items.count) / \(ClipboardStore.maxItems)")
                LabeledContent("저장 위치") {
                    Button("Finder에서 보기") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.persistence.baseURL])
                    }
                }
                Button("히스토리 전체 삭제", role: .destructive) {
                    store.clearAll()
                }
                .disabled(store.items.isEmpty)
            }
            Section {
                Text("비밀번호 관리자 등이 표시한 민감 데이터(Concealed/Transient/AutoGenerated)는 수집하지 않습니다. 이미지 OCR은 기기 내에서 처리됩니다(한국어·영어).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
