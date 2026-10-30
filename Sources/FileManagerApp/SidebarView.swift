import AppKit
import FileManagerCore
import SwiftUI

/// Pinned folders, recent folders, drives (with Eject) and a folder tree of Home that opens
/// down to the current folder, like Explorer's navigation pane. Every folder row is a drop
/// target; dropping between pinned folders pins.
struct SidebarView: View {
    var model: BrowserModel
    /// Read when the sidebar appears, not as the initial value: that would be read again (disk
    /// and network I/O) every time the window's body makes a new SidebarView.
    @State private var volumes: [Volume] = []
    /// The folder tree's root: Home, or in snapshot runs the demo folder, so a test never lists
    /// folders outside it (which can bring up macOS's folder-access prompts for a new build).
    private var treeRoot: URL {
        Windows.snapshotFolder.map { URL(filePath: $0) } ?? model.home
    }
    @State private var tree = FolderTree()
    /// The row last clicked: it keeps the highlight while its folder is open, so a recent or
    /// tree row stays lit (and in view) rather than the highlight moving elsewhere.
    @State private var clicked: SidebarTag?
    private var store: SidebarStore { .shared }

    var body: some View {
        ScrollViewReader { scroller in
            List(selection: selectionBinding) {
                Section("Pinned") {
                    ForEach(store.pins.paths, id: \.self) { path in
                        row(URL(filePath: path), section: .pinned, symbol: Self.symbol(for: path), draggable: true)
                            .contextMenu {
                                openInNewTab(path)
                                Button("Remove from Sidebar") { store.unpin(path) }
                            }
                    }
                    .onMove { store.movePins(from: $0, to: $1) }
                    .onInsert(of: [.fileURL]) { index, providers in pinDropped(providers, at: index) }
                }
                let recent = recentShown
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(Array(recent), id: \.self) { path in
                            row(URL(filePath: path), section: .recent, symbol: "clock")
                                .contextMenu {
                                    openInNewTab(path)
                                    Button("Add to Sidebar") { store.pin([path]) }
                                    Button("Remove from Recent") { store.forget(path) }
                                }
                        }
                    }
                }
                Section("Locations") {
                    ForEach(volumes) { volume in
                        FolderNode(
                            url: volume.url, title: volume.name, symbol: volume.symbol, section: .tree,
                            tree: tree, model: model, eject: volume.isEjectable ? { eject(volume) } : nil)
                    }
                }
                Section("Folders") {
                    FolderNode(
                        url: treeRoot, title: FileManager.default.displayName(atPath: treeRoot.path),
                        symbol: Windows.isSnapshotRun ? "folder" : "house", section: .tree, tree: tree, model: model,
                        eject: nil)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: model.url, initial: true) {
                tree.reveal(model.url, roots: [treeRoot] + volumes.map(\.url))
                // To the highlighted row: a pinned folder's own row, not its place in the tree.
                if let tag = selectionBinding.wrappedValue { scroller.scrollTo(tag) }
            }
            .onChange(of: volumes) { tree.reveal(model.url, roots: [treeRoot] + volumes.map(\.url)) }
            .onChange(of: model.listingVersion) { tree.forget(model.url) }
            .onChange(of: model.showHiddenFiles) { tree.forgetAll() }
        }
        .task { volumes = Volume.mounted() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = Volume.mounted()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = Volume.mounted()
        }
    }

    private func row(_ url: URL, section: SidebarTag.Section, symbol: String, draggable: Bool = false) -> some View {
        // Desktop, Documents and Downloads by their own names: asking for the localized one
        // can bring up macOS's folder-access prompt before they're opened.
        let title =
            url.isGuardedFolder(home: model.home) ? url.lastPathComponent : FileManager.default.displayName(atPath: url.path)
        return Label(title, systemImage: symbol)
            .modifier(SidebarHover())
            .background { if draggable { Color.clear.fadedDragImage(title: title, symbol: symbol) } }
            .tag(SidebarTag(section: section, path: url.path))
            .id(SidebarTag(section: section, path: url.path))
            .folderDropTarget(url, model: model)
    }

    private func openInNewTab(_ path: String) -> some View {
        Button("Open in New Tab") { model.openInNewTabs([URL(filePath: path)]) }
    }

    /// Highlights the current folder: the row it was opened from, else its pinned row, else
    /// its place in the tree; picking a row opens it.
    private var selectionBinding: Binding<SidebarTag?> {
        Binding(
            get: {
                let path = model.url.path
                if let clicked, clicked.path == path, isShown(clicked) { return clicked }
                if store.pins.isPinned(path) { return SidebarTag(section: .pinned, path: path) }
                return SidebarTag(section: .tree, path: path)
            },
            set: { tag in
                guard let tag else { return }
                clicked = tag
                guard !URL(filePath: tag.path).isSameFile(as: model.url) else { return }
                model.navigate(to: URL(filePath: tag.path))
                model.focusList()
            }
        )
    }

    /// The Recent section: the last eight folders that aren't pinned.
    private var recentShown: ArraySlice<String> {
        store.recent.paths.filter { !store.pins.isPinned($0) }.prefix(8)
    }

    /// Whether the row is still in the sidebar (a recent folder that's been pinned isn't).
    private func isShown(_ tag: SidebarTag) -> Bool {
        switch tag.section {
        case .pinned: store.pins.isPinned(tag.path)
        case .recent: recentShown.contains(tag.path)
        case .tree: true
        }
    }

    /// Folders dropped between pinned rows are pinned there.
    private func pinDropped(_ providers: [NSItemProvider], at index: Int) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.hasDirectoryPath || Self.isFolder(url) else { return }
                Task { @MainActor in SidebarStore.shared.pin([url.normalized.path], at: index) }
            }
        }
    }

    private func eject(_ volume: Volume) {
        let url = volume.url
        let window = model.window
        Task {
            do {
                try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }.value
            } catch {
                FileOperations.shared.showError(error, title: "Can't eject “\(volume.name)”", window: window)
            }
        }
    }

    nonisolated static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    static func symbol(for path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch path {
        case home: return "house"
        case home + "/Desktop": return "menubar.dock.rectangle"
        case home + "/Documents": return "doc"
        case home + "/Downloads": return "arrow.down.circle"
        case "/Applications": return "square.grid.3x3"
        case home + "/Library/Mobile Documents/com~apple~CloudDocs": return "icloud"
        default: return "folder"
        }
    }
}

/// A sidebar row's identity: the same folder can be pinned and in the tree.
struct SidebarTag: Hashable {
    enum Section: Hashable { case pinned, recent, tree }
    var section: Section
    var path: String
}

/// A folder in the tree, with its subfolders loaded when it's opened.
private struct FolderNode: View {
    let url: URL
    let title: String
    let symbol: String
    let section: SidebarTag.Section
    let tree: FolderTree
    let model: BrowserModel
    let eject: (() -> Void)?

    var body: some View {
        DisclosureGroup(isExpanded: tree.binding(for: url)) {
            // Only list a folder once it's open: DisclosureGroup builds its content even when
            // closed, and reading every subfolder's subfolders would walk the whole disk.
            if tree.isExpanded(url) {
                ForEach(tree.children(of: url, showHidden: model.showHiddenFiles), id: \.self) { child in
                    FolderNode(
                        url: child, title: child.lastPathComponent, symbol: "folder", section: section, tree: tree,
                        model: model, eject: nil)
                }
            }
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                if let eject {
                    Spacer()
                    Button("Eject", systemImage: "eject", action: eject)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Eject “\(title)”")
                }
            }
            .modifier(SidebarHover())
            .tag(SidebarTag(section: section, path: url.path))
            .id(SidebarTag(section: section, path: url.path))
            .folderDropTarget(url, model: model)
            .contextMenu {
                Button("Open in New Tab") { model.openInNewTabs([url]) }
                Button("Add to Sidebar") { SidebarStore.shared.pin([url.path]) }
                if let eject { Button("Eject", action: eject) }
            }
        }
    }
}

/// Which tree folders are open, and their subfolders (cached until the folder changes).
/// `expanded` is only written when it really changes: any write to an observed set re-renders
/// the tree, and DisclosureGroup writes its state back while rendering, so an unconditional
/// write loops forever and starves the main thread. Subfolders are read in the background (a
/// network folder would stall drawing) and show up when read; `children` is written only when
/// a folder's list really changes, for the same reason.
@MainActor @Observable
final class FolderTree {
    private(set) var expanded: Set<String> = []
    private var children: [String: [URL]] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private var showHidden = false
    /// Bumped by `forgetAll`, so a read started before it is dropped.
    @ObservationIgnored private var generation = 0

    func binding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { self.expanded.contains(url.path) },
            set: { open in
                guard open != self.expanded.contains(url.path) else { return }
                if open {
                    // Read again on opening; the last list shows meanwhile.
                    self.load(url)
                    self.expanded.insert(url.path)
                } else {
                    self.expanded.remove(url.path)
                }
            })
    }

    func isExpanded(_ url: URL) -> Bool { expanded.contains(url.path) }

    /// The subfolders read so far (none until the first read is in).
    func children(of url: URL, showHidden: Bool) -> [URL] {
        // Reads use it; a change is dealt with by `forgetAll` (called when hidden files are toggled).
        self.showHidden = showHidden
        if let read = children[url.path] { return read }
        // Drawing is in progress: start the read after it.
        Task { self.load(url) }
        return []
    }

    private func load(_ url: URL) {
        let path = url.path
        guard loading.insert(path).inserted else { return }
        let showHidden = showHidden, generation = generation
        Task {
            let folders = await Task.detached(priority: .userInitiated) {
                let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: keys, options: showHidden ? [] : [.skipsHiddenFiles])) ?? []
                return urls.filter { SidebarView.isFolder($0) }
                    .map(\.normalized)
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }.value
            loading.remove(path)
            guard generation == self.generation, children[path] != folders else { return }
            children[path] = folders
        }
    }

    /// Opens the tree down to `url` under the most specific root it's in.
    func reveal(_ url: URL, roots: [URL]) {
        let path = url.path
        guard let root = roots.map(\.path)
            .filter({ path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") })
            .max(by: { $0.count < $1.count })
        else { return }
        var folder = (path as NSString).deletingLastPathComponent
        var open: [String] = []
        while folder.count >= root.count, folder != path {
            open.append(folder)
            if folder == root || folder == "/" { break }
            folder = (folder as NSString).deletingLastPathComponent
        }
        if !expanded.isSuperset(of: open) { expanded.formUnion(open) }
    }

    /// The folder changed: read it again if it has been read (its list stays up meanwhile).
    func forget(_ url: URL) {
        if children[url.path] != nil { load(url) }
    }

    func forgetAll() {
        generation += 1
        loading.removeAll()
        if !children.isEmpty { children.removeAll() }
    }
}

/// A mounted disk in Locations.
struct Volume: Identifiable, Hashable {
    var url: URL
    var name: String
    var symbol: String
    var isEjectable: Bool
    var id: URL { url }

    static func mounted() -> [Volume] {
        // Snapshot runs leave disks alone (network and removable ones can prompt for access).
        if Windows.isSnapshotRun { return [] }
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
            .volumeIsLocalKey, .volumeIsRootFileSystemKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isRoot = url.path == "/" || values?.volumeIsRootFileSystem == true
            let isNetwork = values?.volumeIsLocal == false
            let symbol =
                isNetwork ? "server.rack"
                : isRoot || values?.volumeIsInternal == true ? "internaldrive"
                : "externaldrive"
            let ejectable = !isRoot && (isNetwork || values?.volumeIsEjectable == true || values?.volumeIsRemovable == true)
            return Volume(
                url: url.normalized, name: values?.volumeLocalizedName ?? url.lastPathComponent, symbol: symbol,
                isEjectable: ejectable)
        }
    }
}

extension View {
    /// Files dropped here are moved or copied into `folder` (same rules as the file list).
    func folderDropTarget(_ folder: URL, model: BrowserModel) -> some View {
        dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            let operation = FileDrop.operation(files, into: folder)
            guard !files.isEmpty, operation != .none else { return false }
            model.drop(files, into: folder, operation: operation)
            return true
        }
    }
}
