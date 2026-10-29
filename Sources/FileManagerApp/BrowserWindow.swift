import FileManagerCore
import SwiftUI

/// One window: sidebar, toolbar with back/forward/up and the address bar, file list, status bar.
struct BrowserWindow: View {
    let spec: WindowSpec
    @State private var model: BrowserModel
    @AppStorage(SettingsKey.foldersFirst) private var foldersFirst = true
    @AppStorage(SettingsKey.showPreviewPane) private var showPreview = false
    @AppStorage(SettingsKey.showAllExtensions) private var showAllExtensions = true
    @Environment(\.openWindow) private var openWindow

    init(spec: WindowSpec) {
        self.spec = spec
        _model = State(initialValue: BrowserModel(start: spec.path.map { URL(filePath: $0) }, id: spec.id))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            HSplitView {
                VStack(spacing: 0) {
                    if model.isSearchOpen {
                        SearchBar(model: model)
                        Divider()
                    }
                    Group {
                        switch model.view.mode {
                        case .details: FileListView(model: model)
                        case .icons: FileIconView(model: model)
                        }
                    }
                    .overlay { emptyOrError }
                    StatusBar(model: model)
                }
                .frame(minWidth: 320, maxWidth: .infinity)
                if showPreview {
                    PreviewPane(model: model)
                }
            }
        }
        .navigationTitle(model.title)
        // The address bar shows where you are; the title would only crowd it out. The title is
        // still used by the Window menu.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") { model.perform(.goBack) }
                    .disabled(!model.canPerform(.goBack))
                    .help("Back (Opt+Left)")
                Button("Forward", systemImage: "chevron.right") { model.perform(.goForward) }
                    .disabled(!model.canPerform(.goForward))
                    .help("Forward (Opt+Right)")
                Button("Up", systemImage: "arrow.up") { model.perform(.goUp) }
                    .disabled(!model.canPerform(.goUp))
                    .help("Enclosing folder (Backspace)")
            }
            // One item, so the address bar and the view buttons share the width rather than the
            // toolbar pushing the address bar into its overflow menu.
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    AddressBar(model: model)
                    viewButtons
                }
            }
        }
        .background(KeyMonitor(model: model))
        .frame(minWidth: 640, minHeight: 360)
        .onAppear {
            Windows.shared.register(model, spec: spec)
            model.foldersFirst = foldersFirst
            model.start()
            if let reveal = spec.reveal { model.refresh(selecting: [URL(filePath: reveal)]) }
            model.focusList()
            // The first window at launch reopens the rest of last session's windows and tabs.
            for other in Windows.shared.takeRestoreQueue() { openWindow(value: other) }
        }
        .sheet(item: $model.batchRename) { request in
            BatchRenameView(request: request, model: model)
        }
        .onChange(of: model.openRequestCount) {
            for request in model.takeOpenRequests() { openWindow(value: request) }
        }
        .onChange(of: foldersFirst) { model.foldersFirst = foldersFirst }
        .onChange(of: showAllExtensions) { model.refresh() }
        // The new view takes over the keyboard focus the old one had.
        .onChange(of: model.view.mode) { model.focusList() }
        .onChange(of: model.infoRequestCount) {
            openWindow(id: InfoWindow.id, value: model.infoRequest)
        }
        .onChange(of: FileOperations.shared.showProgress) {
            if FileOperations.shared.showProgress, ActiveBrowser.shared.model === model {
                openWindow(id: OperationsWindow.id)
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugNavigate)) { note in
            if let url = note.object as? URL { model.navigate(to: url) }
        }
        #endif
    }

    private var viewButtons: some View {
        HStack(spacing: 6) {
            ControlGroup {
                viewButton(.viewAsIcons, mode: .icons, symbol: "square.grid.2x2", keys: "Shift+Cmd+2")
                viewButton(.viewAsDetails, mode: .details, symbol: "list.bullet", keys: "Shift+Cmd+6")
            }
            .fixedSize()
            Toggle("Preview", systemImage: "sidebar.right", isOn: $showPreview)
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help("Preview pane (Opt+P)")
        }
    }

    /// The current view's button is tinted.
    private func viewButton(_ action: Action, mode: FolderView.Mode, symbol: String, keys: String) -> some View {
        Button(mode.title, systemImage: symbol) { model.perform(action) }
            .labelStyle(.iconOnly)
            .foregroundStyle(model.view.mode == mode ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help("\(mode.title) (\(keys))")
    }

    @ViewBuilder private var emptyOrError: some View {
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
