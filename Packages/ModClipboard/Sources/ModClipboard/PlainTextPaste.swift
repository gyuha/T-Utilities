import AppKit

/// Pastes the current clipboard text without formatting: temporarily reduces the
/// pasteboard to a single `.string` entry, sends ⌘V to the focused app, then restores
/// the original (rich) items.
@MainActor
enum PlainTextPaste {
    /// Every item of the pasteboard as raw type → data pairs.
    struct Snapshot {
        let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]
    }

    /// Replaces the pasteboard contents with their plain-text form.
    /// Returns the original contents, or `nil` (pasteboard untouched) when there is no text.
    static func replaceWithPlainText(on pasteboard: NSPasteboard) -> Snapshot? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type: type, data: $0) } }
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return Snapshot(items: items)
    }

    static func restore(_ snapshot: Snapshot, on pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = snapshot.items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }

    /// Hotkey action: paste the clipboard text as plain text into the focused app.
    /// `willWrite` runs before each pasteboard write so the history monitor can ignore it.
    static func perform(willWrite: @escaping @MainActor () -> Void) {
        let pasteboard = NSPasteboard.general
        willWrite()
        guard let snapshot = replaceWithPlainText(on: pasteboard) else { return }
        Paster.postCommandV()
        Task { @MainActor in
            // Give the target app time to read the pasteboard before the original comes back.
            try? await Task.sleep(for: .milliseconds(300))
            willWrite()
            restore(snapshot, on: pasteboard)
        }
    }
}
