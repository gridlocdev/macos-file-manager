import FileManagerCore
import SwiftUI

/// One window: sidebar, toolbar with back/forward/up and the address bar, file list, status bar.
/// F3 splits it into two panes side by side; the toolbar, sidebar, menus and preview follow the
/// active pane (the one whose list last had the keyboard focus).
struct BrowserWindow: View {
    let spec: WindowSpec
    @State private var model: BrowserModel
    /// The right-hand pane while split.
    @State private var split: BrowserModel?
    @State private var activeID: UUID
    @State private var connecting = false
    @AppStorage(SettingsKey.showPreviewPane) private var showPreview = false
    @Environment(\.openWindow) private var openWindow

    init(spec: WindowSpec) {
        self.spec = spec
        let model = BrowserModel(start: spec.path.map { URL(filePath: $0) }, id: spec.id)
        _model = State(initialValue: model)
        _activeID = State(initialValue: model.id)
    }

    private var active: BrowserModel { split.flatMap { $0.id == activeID ? $0 : nil } ?? model }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: active)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            HSplitView {
                pane(model)
                if let split { pane(split) }
                if showPreview {
                    PreviewPane(model: active)
                }
            }
        }
        // Split, both folders, left first ("Documents + Downloads").
        .navigationTitle(split.map { "\(model.title) + \($0.title)" } ?? model.title)
        // The address bar shows where you are; the title would only crowd it out. The title is
        // still used by the tab bar and the Window menu.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") { active.perform(.goBack) }
                    .disabled(!active.canPerform(.goBack))
                    .help("Back (Opt+Left)")
                    .pointerCursor()
                Button("Forward", systemImage: "chevron.right") { active.perform(.goForward) }
                    .disabled(!active.canPerform(.goForward))
                    .help("Forward (Opt+Right)")
                    .pointerCursor()
                Button("Up", systemImage: "arrow.up") { active.perform(.goUp) }
                    .disabled(!active.canPerform(.goUp))
                    .help("Enclosing folder (Backspace)")
                    .pointerCursor()
            }
            // One item, so the address bar and the view buttons share the width rather than the
            // toolbar pushing the address bar into its overflow menu.
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AddressBar(model: active)
                        .id(active.id)
                    viewButtons
                }
            }
        }
        .background(KeyMonitor(model: model, active: active))
        .frame(minWidth: 640, minHeight: 360)
        .onAppear {
            Windows.shared.register(model, spec: spec)
            model.onFocused = { activeID = model.id }
            model.start()
            if let reveal = spec.reveal { model.refresh(selecting: [URL(filePath: reveal)]) }
            model.focusList()
            // The first window at launch reopens the rest of last session's windows and tabs.
            for other in Windows.shared.takeRestoreQueue() { openWindow(value: other) }
        }
        .sheet(isPresented: $connecting) {
            ConnectToServerView(model: active)
        }
        .onChange(of: FileOperations.shared.showProgress) {
            if FileOperations.shared.showProgress, ActiveBrowser.shared.model === active {
                openWindow(id: OperationsWindow.id)
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugNavigate)) { note in
            if let url = note.object as? URL { model.navigate(to: url) }
        }
        #endif
    }

    /// One pane: (with a split view) a heading, then the find bar, the files and the status bar.
    private func pane(_ pane: BrowserModel) -> some View {
        VStack(spacing: 0) {
            if split != nil {
                PaneHeader(model: pane, isActive: pane === active)
                Divider()
            }
            if pane.isSearchOpen {
                SearchBar(model: pane)
                Divider()
            }
            Group {
                switch pane.view.mode {
                case .details: FileListView(model: pane)
                case .icons: FileIconView(model: pane)
                }
            }
            .overlay { EmptyOrError(model: pane) }
            StatusBar(model: pane)
        }
        .frame(minWidth: 240, maxWidth: .infinity)
        .modifier(PaneEvents(model: pane))
        .onPaneCommand(pane) { command in
            switch command {
            case .toggleSplit: toggleSplit()
            case .connectToServer: connecting = true
            case .getInfo(let urls): openWindow(id: InfoWindow.id, value: urls)
            case .open(let spec): openWindow(value: spec)
            default: break
            }
        }
    }

    /// F3: open a second pane on the active pane's folder, or close the split, keeping the folder
    /// of whichever pane was active (as in Dolphin).
    private func toggleSplit() {
        if let right = split {
            if right === active { model.navigate(to: right.url) }
            model.otherPane = nil
            right.stop()
            split = nil
            activeID = model.id
            model.focusList()
            return
        }
        let right = BrowserModel(start: active.url)
        right.hostID = model.id
        right.window = model.window
        right.foldersFirst = model.foldersFirst
        right.showHiddenFiles = model.showHiddenFiles
        right.otherPane = model
        model.otherPane = right
        right.onFocused = { activeID = right.id }
        split = right
        activeID = right.id
        right.start()
        right.focusList()
    }

    private var viewButtons: some View {
        HStack(spacing: 6) {
            ControlGroup {
                viewButton(.viewAsIcons, mode: .icons, symbol: "square.grid.2x2", keys: "Opt+Cmd+1")
                viewButton(.viewAsDetails, mode: .details, symbol: "list.bullet", keys: "Opt+Cmd+2")
            }
            .fixedSize()
            Button("Split View", systemImage: "rectangle.split.2x1") { active.perform(.toggleSplitView) }
                .labelStyle(.iconOnly)
                .foregroundStyle(split != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .help("Split view (F3)")
                .pointerCursor()
            Toggle("Preview", systemImage: "sidebar.right", isOn: $showPreview)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help("Preview pane (Opt+P)")
                .pointerCursor()
        }
    }

    /// The current view's button is tinted.
    private func viewButton(_ action: Action, mode: FolderView.Mode, symbol: String, keys: String) -> some View {
        Button(mode.title, systemImage: symbol) { active.perform(action) }
            .labelStyle(.iconOnly)
            .foregroundStyle(active.view.mode == mode ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help("\(mode.title) (\(keys))")
            .pointerCursor()
    }
}

/// What each pane needs from the window besides its commands: batch rename, settings.
private struct PaneEvents: ViewModifier {
    @Bindable var model: BrowserModel
    @AppStorage(SettingsKey.foldersFirst) private var foldersFirst = true
    @AppStorage(SettingsKey.showAllExtensions) private var showAllExtensions = true

    func body(content: Content) -> some View {
        content
            .onAppear { model.foldersFirst = foldersFirst }
            .sheet(item: $model.batchRename) { request in
                BatchRenameView(request: request, model: model)
            }
            .onChange(of: foldersFirst) { model.foldersFirst = foldersFirst }
            .onChange(of: showAllExtensions) { model.refresh() }
            // The new view takes over the keyboard focus the old one had.
            .onChange(of: model.view.mode) { model.focusList() }
    }
}

/// A split pane's heading: its folder, highlighted on the active pane. Clicking it makes the
/// pane active.
private struct PaneHeader: View {
    var model: BrowserModel
    var isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(model.title).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .font(.callout.weight(isActive ? .semibold : .regular))
        .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(isActive ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.bar))
        .contentShape(Rectangle())
        .onTapGesture { model.focusList() }
        .pointerCursor()
        .help(model.url.path)
        .accessibilityLabel(isActive ? "\(model.title), active pane" : model.title)
    }
}

private struct EmptyOrError: View {
    var model: BrowserModel

    var body: some View {
        if let message = model.errorMessage {
            ContentUnavailableView("Can't Open Folder", systemImage: "lock", description: Text(message))
        } else if model.items.isEmpty && !model.isLoading && !model.isSearching {
            Text(model.isFiltering ? "No items match" : "This folder is empty").foregroundStyle(.secondary)
        }
    }
}

struct StatusBar: View {
    var model: BrowserModel

    var body: some View {
        HStack(spacing: 8) {
            Text(summary)
            if model.isLoading || model.isSearching { ProgressView().controlSize(.small) }
            Spacer()
            if model.showHiddenFiles { Text("Showing hidden files") }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    /// "12 items, 3 selected (4.2 MB), 120 GB available", like Explorer's status bar. While
    /// finding: "3 of 40 items" in the folder, "120 found" in subfolders.
    private var summary: String {
        let count = model.items.count
        var text = count == 1 ? "1 item" : "\(count) items"
        if model.isSearchingSubfolders {
            text = model.isSearching ? "Searching… \(count) found" : "\(count) found in subfolders"
            if model.searchHitLimit { text += " (stopped at \(FolderSearch.limit))" }
        } else if model.isFiltering {
            text = "\(count) of \(model.folderItemCount) items"
        }
        if !model.selection.isEmpty {
            text += ", \(model.selection.count) selected"
            let size = model.selectionSize
            if size > 0 { text += " (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))" }
        }
        if let free = model.freeSpace {
            text += ", \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) available"
        }
        return text
    }
}
