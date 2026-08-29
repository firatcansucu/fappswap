import AppKit
import FappSwapCore
import SwiftUI

/// The panel's frame: update banner on top, sidebar and content in the middle,
/// status line and Quit along the bottom. Fixed size — see the note on
/// `StatusPanelController.width`; the tabs scroll inside it rather than the
/// window resizing around them.
struct StatusPanelView: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        VStack(spacing: 0) {
            UpdateBanner(model: model)
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
        }
        .frame(width: StatusPanelController.width, height: StatusPanelController.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(StatusPanelModel.PanelTab.allCases, id: \.self) { tab in
                Button {
                    // Leaving a tab closes its editor — which is also what resumes
                    // the tap if that editor was a recorder.
                    model.activeEditor = nil
                    model.tab = tab
                } label: {
                    // Icon and label on ONE line — spec decision 2.
                    Label(tab.title, systemImage: tab.symbol)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(
                            model.tab == tab ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(8)
        .frame(width: 140)
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .shortcuts: ShortcutsTab(model: model)
        case .snippets: SnippetsTab(model: model)
        case .clipboard: ClipboardTab(model: model)
        case .reminders: RemindersTab(model: model)
        case .general: GeneralTab(model: model)
        }
    }

    private var footer: some View {
        HStack {
            if model.statusLine == .noPermission {
                Button(model.statusLine.text) { model.settings.openAccessibilitySettings() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            } else {
                Text(model.statusLine.text).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Mirrors `UpdateController.State` across the top of the panel. Hidden when
/// idle: the check that runs on a timer must not put a bar over the panel every
/// time it finds nothing. "Check for Updates" as a user-initiated action lives in
/// the General tab.
struct UpdateBanner: View {
    @ObservedObject var model: StatusPanelModel

    var body: some View {
        switch model.updateState {
        case .idle:
            EmptyView()
        case .checking:
            banner { Text("Checking for updates…").foregroundStyle(.secondary) }
        case .available(let version):
            banner {
                Text("Update to \(version) available")
                Spacer()
                Button("Install") { model.updateAction() }
            }
        case .working(let phase):
            banner { Text(phase).foregroundStyle(.secondary) }
        case .failed(let message):
            banner {
                Text(message).foregroundStyle(.red).lineLimit(1)
                Spacer()
                Button("Retry") { model.updateAction() }
            }
        }
    }

    private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8, content: content)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Divider()
        }
    }
}
