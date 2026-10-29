import AppKit
import FileManagerCore
import SwiftUI

/// Explorer's address bar: the path as clickable segments, each with a › menu of its subfolders.
/// Clicking the empty part, Cmd+L or Opt+D turns it into a text field for typing a path.
struct AddressBar: View {
    @Bindable var model: BrowserModel
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("Path", text: $model.addressText)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .padding(.horizontal, 10)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit { model.submitAddress() }
                    .onExitCommand { model.cancelAddressEdit() }
                    .onKeyPress(.tab) {
                        model.completeAddress()
                        return .handled
                    }
                    .help("Type a path and press Return. Tab completes folder names. Esc cancels.")
                    .accessibilityLabel("Address")
            } else {
                Breadcrumbs(model: model) { editing = true }
            }
        }
        .frame(minWidth: 160, idealWidth: 300, maxWidth: .infinity)
        .onPaneCommand(model) { command in
            guard case .focusAddressBar = command else { return }
            editing = true
            focused = true
        }
        .onChange(of: focused) {
            guard !focused else { return }
            editing = false
            model.addressText = PathInput.display(model.url, home: model.home)
        }
    }
}

private struct Breadcrumbs: View {
    var model: BrowserModel
    var startEditing: () -> Void

    var body: some View {
        let segments = FileManagerCore.Breadcrumbs.segments(
            for: model.url, volumes: Self.volumeNames(), startupDiskName: Self.startupDiskName)
        HStack(spacing: 0) {
            // The longest tail of the path that fits; earlier folders go in a "…" menu.
            ViewThatFits(in: .horizontal) {
                ForEach(0..<segments.count, id: \.self) { hidden in
                    trail(Array(segments.dropFirst(hidden)), hidden: Array(segments.prefix(hidden)))
                }
            }
            .layoutPriority(1)
            // The empty part: click to type a path.
            Color.clear
                .frame(minWidth: 24, maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: startEditing)
        }
        // No box of its own: the toolbar draws the capsule around it, and a second rounded box
        // inside gets its corners clipped by the capsule's curve.
        .padding(.horizontal, 10)
        .frame(height: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Address")
    }

    private func trail(_ visible: [FileManagerCore.Breadcrumbs.Segment], hidden: [FileManagerCore.Breadcrumbs.Segment]) -> some View {
        HStack(spacing: 0) {
            if !hidden.isEmpty {
                Menu("…") {
                    ForEach(hidden.reversed(), id: \.url) { segment in
                        Button(segment.title) { go(segment.url) }
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Folders further up")
            }
            ForEach(visible, id: \.url) { segment in
                Button(segment.title) { go(segment.url) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(segment.url.isSameFile(as: model.url) ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 3)
                SubfolderMenu(folder: segment.url, showHidden: model.showHiddenFiles, current: model.url) { go($0) }
            }
        }
        .fixedSize()
    }

    private func go(_ url: URL) {
        model.navigate(to: url)
        model.focusList()
    }

    static var startupDiskName: String {
        (try? URL(filePath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "/"
    }

    static func volumeNames() -> [String: String] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeLocalizedNameKey], options: [.skipHiddenVolumes]) ?? []
        var names: [String: String] = [:]
        for url in urls {
            names[url.path] = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName)
                ?? url.lastPathComponent
        }
        return names
    }
}

/// The › after a segment: a menu of the folders inside it, like Explorer's address bar arrows.
private struct SubfolderMenu: View {
    let folder: URL
    let showHidden: Bool
    let current: URL
    let go: (URL) -> Void

    var body: some View {
        Menu {
            let children = Self.subfolders(of: folder, showHidden: showHidden)
            if children.isEmpty {
                Text("No folders")
            }
            ForEach(children, id: \.self) { child in
                Button {
                    go(child)
                } label: {
                    // Mark the folder that's on the current path.
                    if current.isSameFile(as: child) || current.isInside(child) {
                        Label(child.lastPathComponent, systemImage: "checkmark")
                    } else {
                        Text(child.lastPathComponent)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.compact.right")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Folders in \(folder.lastPathComponent.isEmpty ? "/" : folder.lastPathComponent)")
    }

    static func subfolders(of folder: URL, showHidden: Bool) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: showHidden ? [] : [.skipsHiddenFiles])) ?? []
        return urls.filter {
            let values = try? $0.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isPackage != true
        }
        .map(\.normalized)
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        .prefix(300)
        .map { $0 }
    }
}
