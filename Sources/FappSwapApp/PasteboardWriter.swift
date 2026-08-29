import AppKit

/// The one place the app makes pasteboard writes that must NOT be recorded as a
/// user copy — the expander's borrow-and-restore, the panel's own writes. Every
/// write records the resulting `changeCount`, so `ClipboardRecorder` can tell
/// these from the user's real copies and skip them. A deliberate user-facing
/// copy — the Snippets tab's "copy snippet", for one — writes to
/// `NSPasteboard.general` directly instead, on purpose: that's a real copy and
/// should show up in clipboard history. Main thread only.
final class PasteboardWriter {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    private let pasteboard = NSPasteboard.general
    /// `changeCount`s this object produced that the recorder has not yet seen.
    /// Bounded because the recorder may be stopped (feature disabled) and never
    /// consume them.
    private var ownChangeCounts = Set<Int>()
    private static let maxRemembered = 64

    func write(text: String) {
        perform { $0.setString(text, forType: .string) }
    }

    /// PNG plus a TIFF rendering, because some apps read only one of them.
    func write(png: Data) {
        perform { pasteboard in
            pasteboard.setData(png, forType: .png)
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
    }

    /// One dictionary per pasteboard item, type to data.
    ///
    /// Known limitation: promised or lazily-provided data (some apps' large
    /// file promises) reports a type but returns no data here, so it cannot be
    /// snapshotted and is lost. Plain text — the overwhelmingly common case —
    /// restores correctly.
    func snapshot() -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    func restore(_ snapshot: Snapshot) {
        perform { pasteboard in
            let items: [NSPasteboardItem] = snapshot.compactMap { entry in
                guard !entry.isEmpty else { return nil }
                let item = NSPasteboardItem()
                for (type, data) in entry { item.setData(data, forType: type) }
                return item
            }
            guard !items.isEmpty else { return }
            pasteboard.writeObjects(items)
        }
    }

    /// True exactly once for each write this object made. The recorder calls it
    /// with every new `changeCount` it notices.
    func consumeOwnChange(_ changeCount: Int) -> Bool {
        ownChangeCounts.remove(changeCount) != nil
    }

    private func perform(_ body: (NSPasteboard) -> Void) {
        pasteboard.clearContents()
        body(pasteboard)
        if ownChangeCounts.count >= Self.maxRemembered { ownChangeCounts.removeAll() }
        ownChangeCounts.insert(pasteboard.changeCount)
    }
}
