import AppKit
import FappSwapCore
import SwiftUI

/// State behind the panel. Reads the store on `reload()`; never mutates it —
/// deletion and paste go through `ClipboardPanelController`.
final class ClipboardPanelModel: ObservableObject {
    @Published var query = "" {
        didSet { refilter() }
    }
    @Published private(set) var visible: [ClipboardItem] = []
    @Published var selectedID: UUID?
    @Published private(set) var totalCount = 0
    @Published private(set) var isPaused = false
    /// Bumped on every open so the view can re-focus the search field.
    @Published var openGeneration = 0

    private let store: ClipboardHistoryStore
    private let pausedState: () -> Bool
    private var iconCache: [String: NSImage] = [:]
    private var thumbnailCache: [UUID: NSImage] = [:]
    /// Mouse position captured when the panel opens, so the hover SwiftUI
    /// synthesizes for a row built under a stationary pointer doesn't override
    /// `selectFirst()`'s choice. Cleared (making hover permissive again) once
    /// the pointer is observed to have actually moved.
    private var mouseLocationAtOpen: NSPoint?

    init(store: ClipboardHistoryStore, isPaused: @escaping () -> Bool) {
        self.store = store
        self.pausedState = isPaused
    }

    var selected: ClipboardItem? {
        visible.first { $0.id == selectedID }
    }

    func reload() {
        totalCount = store.items.count
        isPaused = pausedState()
        let live = Set(store.items.map(\.id))
        thumbnailCache = thumbnailCache.filter { live.contains($0.key) }
        refilter()
    }

    func selectFirst() {
        selectedID = visible.first?.id
        mouseLocationAtOpen = NSEvent.mouseLocation
    }

    /// Called on row hover. Ignored until the pointer has actually moved from
    /// where it was when the panel opened — SwiftUI fires `onHover` for a
    /// stationary pointer merely because the row was just built under it,
    /// which would otherwise steal the selection `selectFirst()` just made.
    func hover(_ id: UUID) {
        if let origin = mouseLocationAtOpen {
            let current = NSEvent.mouseLocation
            guard hypot(current.x - origin.x, current.y - origin.y) > 2 else { return }
            mouseLocationAtOpen = nil
        }
        selectedID = id
    }

    func moveSelection(by delta: Int) {
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visible.count - 1)
        selectedID = visible[next].id
    }

    /// After the controller removes the item at `index` from the store and
    /// calls `reload()`, keeps the selection at the same position.
    func selectAfterRemoving(indexOf id: UUID) {
        let index = visible.firstIndex { $0.id == id } ?? 0
        reload()
        guard !visible.isEmpty else { selectedID = nil; return }
        selectedID = visible[min(index, visible.count - 1)].id
    }

    private func refilter() {
        visible = store.items(matching: query)
        if !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }

    // MARK: - Row decoration

    /// The source app's icon, looked up from the bundle ID and cached for the
    /// session. Nothing is stored on disk; this is what Spotlight does.
    func icon(for bundleID: String?) -> NSImage {
        let key = bundleID ?? ""
        if let cached = iconCache[key] { return cached }
        let icon: NSImage
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .data)
        }
        iconCache[key] = icon
        return icon
    }

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        if let cached = thumbnailCache[item.id] { return cached }
        guard let url = store.thumbnailURL(for: item), let image = NSImage(contentsOf: url) else { return nil }
        thumbnailCache[item.id] = image
        return image
    }

    func subtitle(for item: ClipboardItem) -> String {
        let app = item.sourceBundleID.flatMap(AppInfo.displayName(for:)) ?? "Unknown app"
        return "\(app) · \(Self.relativeTime(item.date))"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .named
        return f
    }()
    private static let absolute: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let age = now.timeIntervalSince(date)
        if age < 60 { return "just now" }
        if age < 7 * 86_400 { return relative.localizedString(for: date, relativeTo: now) }
        return absolute.string(from: date)
    }
}

struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardPanelModel
    let onCopy: (ClipboardItem) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search clipboard history", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .focused($searchFocused)

            Divider()

            if model.visible.isEmpty {
                Text(model.totalCount == 0 ? "Nothing copied yet" : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.visible) { item in
                                ClipboardRow(
                                    item: item,
                                    icon: model.icon(for: item.sourceBundleID),
                                    thumbnail: model.thumbnail(for: item),
                                    subtitle: model.subtitle(for: item),
                                    isSelected: item.id == model.selectedID,
                                    onCopy: { onCopy(item) })
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering { model.hover(item.id) }
                                }
                                .onTapGesture { model.selectedID = item.id }
                            }
                        }
                    }
                    .onChange(of: model.selectedID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: nil) }
                    }
                }
            }

            Divider()

            HStack {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↩ paste · ⌘C copy · ⌫ delete")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 560, height: 420)
        .onAppear { searchFocused = true }
        .onChange(of: model.openGeneration) { _, _ in
            // The hop lets the window finish becoming key before focus is asked for.
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var footer: String {
        let count = model.totalCount == 1 ? "1 item" : "\(model.totalCount) items"
        return model.isPaused ? "\(count) · Recording paused" : count
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let icon: NSImage
    let thumbnail: NSImage?
    let subtitle: String
    let isSelected: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                switch item.content {
                case .text(let text):
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .lineLimit(2)
                        .truncationMode(.tail)
                case .image(let ref):
                    HStack(spacing: 8) {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text(verbatim: "Image · \(ref.pixelWidth) × \(ref.pixelHeight)")
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isSelected {
                Button("Copy", action: onCopy)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}
