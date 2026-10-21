import AppKit
import KeyboardShortcuts
import SwiftUI
import TUCore

// Adapted from CopyNinja (MIT, © 2026 Dawoon Yi / MelissaSoft) — https://github.com/dwyi84/CopyNinja

extension KeyboardShortcuts.Name {
    static let clipboardToggle = Self("clipboard.toggle", initial: .init(.v, modifiers: [.command, .shift]))
    static let clipboardPlainTextPaste = Self("clipboard.plainTextPaste", initial: .init(.v, modifiers: [.command, .shift, .option]))
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
    @ObservationIgnored private let settings: ModuleSettings
    @ObservationIgnored private let storageURL: URL
    /// App that was frontmost before the popover opened — the paste target.
    @ObservationIgnored private var previousApp: NSRunningApplication?

    /// Return (↩) also pastes into the previously focused app.
    var autoPaste: Bool {
        didSet { settings.set(autoPaste, for: "autoPaste") }
    }
    @ObservationIgnored private var store: ClipboardStore?
    @ObservationIgnored private var monitor: ClipboardMonitor?

    public required convenience init(context: ModuleContext) {
        self.init(context: context, storageURL: PersistenceManager.defaultBaseURL)
    }

    init(context: ModuleContext, storageURL: URL) {
        popover = context.popover
        settings = context.settings
        self.storageURL = storageURL
        autoPaste = context.settings.value("autoPaste", default: false)
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
        previousApp = nil
    }

    public var status: ModuleStatus {
        autoPaste && !Permission.accessibility.isGranted ? .needsPermission(.accessibility) : .running
    }

    public var hotkeys: [HotkeyDefinition] {
        [
            HotkeyDefinition(name: .clipboardToggle, title: "클립보드 열기/닫기") { [popover] in popover.toggle() },
            HotkeyDefinition(name: .clipboardPlainTextPaste, title: "서식 없이 붙여넣기") { [weak self] in
                guard Permission.accessibility.isGranted else {
                    Permission.accessibility.request()
                    return
                }
                PlainTextPaste.perform { self?.monitor?.suppressNextChange() }
            }
        ]
    }

    public func makePopoverSection() -> AnyView? {
        guard let store else { return nil }
        return AnyView(ClipboardSectionView(store: store, autoPaste: autoPaste) { [popover] in popover.close() })
    }

    public func makeSettingsView() -> AnyView {
        guard let store else { return AnyView(EmptyView()) }
        return AnyView(ClipboardSettingsView(module: self, store: store))
    }

    public func popoverWillShow() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost == .current ? nil : frontmost
        store?.prepareForPresentation()
    }

    /// ↩: copy, close, and — when enabled and permitted — paste into the previously focused app.
    private func copyAndPaste(_ item: ClipboardItem, store: ClipboardStore) {
        store.copyToClipboard(item)
        popover.close()
        guard autoPaste, Permission.accessibility.isGranted, let previousApp else { return }
        Paster.paste(into: previousApp)
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
                copyAndPaste(item, store: store)
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
    let module: ClipboardModule
    @ObservedObject var store: ClipboardStore
    @State private var accessibilityGranted = Permission.accessibility.isGranted

    var body: some View {
        Form {
            Section {
                Toggle("↩로 복사하면 현재 입력 위치에 바로 붙여넣기", isOn: Binding(
                    get: { module.autoPaste },
                    set: { enabled in
                        module.autoPaste = enabled
                        if enabled && !accessibilityGranted { Permission.accessibility.request() }
                    }
                ))
                if module.autoPaste && !accessibilityGranted {
                    LabeledContent {
                        Button("허용하기…") { Permission.accessibility.request() }
                    } label: {
                        Label("붙여넣기에는 손쉬운 사용 권한이 필요합니다", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("붙여넣기")
            } footer: {
                Text("팝오버를 열기 전에 사용하던 앱으로 돌아가 ⌘V를 보냅니다. 클릭이나 ⌘1~0은 복사만 합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
        // TCC has no change notification; poll only while this view is visible.
        .task {
            while !Task.isCancelled {
                accessibilityGranted = Permission.accessibility.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
