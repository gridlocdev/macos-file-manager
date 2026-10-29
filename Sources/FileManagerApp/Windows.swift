import AppKit
import FileManagerCore

/// What a browser window (or tab) opens. Each has a fresh id, so every window is distinct.
struct WindowSpec: Codable, Hashable {
    var id = UUID()
    var path: String?
    /// Open as a tab of the window whose model has this id.
    var tabParent: UUID?
    /// Bring this tab to the front once it's in its window (the selected tab of a restored window).
    var select = false
    /// A file to select once the folder is listed (a file opened from another app).
    var reveal: String?
}

/// Every open browser window and tab. Tabs are native macOS window tabs (tab bar, Ctrl+Tab,
/// drag a tab out to a new window), so each tab is a window with its own `BrowserModel`.
/// Also keeps the closed-tab stack and saves the session (windows, tabs, folders) for next launch.
@MainActor
final class Windows {
    static let shared = Windows()

    private struct Entry {
        weak var model: BrowserModel?
        var tabParent: UUID?
        var select: Bool
        var joined = false
    }
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []
    /// Tabs whose parent window hasn't appeared yet (while restoring).
    private var waiting: [UUID: [NSWindow]] = [:]
    private var closedTabs: [String] = []
    private var restoreQueue: [WindowSpec] = []
    private var launchSpecTaken = false
    private var terminating = false
    private var saveTask: Task<Void, Never>?

    private static let sessionKey = "session"
    /// `just snapshot` runs never touch the real session.
    nonisolated static let isSnapshotRun = ProcessInfo.processInfo.environment["FILEMANAGER_SNAPSHOT"] != nil
    /// The demo folder a snapshot run works in.
    nonisolated static let snapshotFolder = isSnapshotRun ? ProcessInfo.processInfo.environment["FILEMANAGER_SNAPSHOT_FOLDER"] : nil

    // MARK: Registration

    func register(_ model: BrowserModel, spec: WindowSpec) {
        guard entries[model.id] == nil else { return }
        order.append(model.id)
        entries[model.id] = Entry(model: model, tabParent: spec.tabParent, select: spec.select)
        join(model)
    }

    /// Called when the model's window exists.
    func attached(_ model: BrowserModel, window: NSWindow) {
        window.tabbingIdentifier = "FileManagerBrowser"
        join(model)
    }

    /// Once a model is both registered and in a window (either can happen first), adds its
    /// window to its parent's tab bar, and any tabs that were waiting for it to its own.
    private func join(_ model: BrowserModel) {
        guard let window = model.window, var entry = entries[model.id], !entry.joined else { return }
        entry.joined = true
        entries[model.id] = entry
        if let parentID = entry.tabParent {
            if let parentWindow = entries[parentID]?.model?.window, entries[parentID]?.joined == true {
                addTab(window, to: parentWindow)
            } else {
                waiting[parentID, default: []].append(window)
            }
        }
        for tab in waiting.removeValue(forKey: model.id) ?? [] { addTab(tab, to: window) }
        scheduleSave()
    }

    private func addTab(_ window: NSWindow, to parent: NSWindow) {
        let anchor = parent.tabGroup?.windows.last ?? parent
        guard anchor !== window else { return }
        anchor.addTabbedWindow(window, ordered: .above)
        let select = order.first { entries[$0]?.model?.window === window }.flatMap { entries[$0]?.select } ?? true
        if select { window.makeKeyAndOrderFront(nil) }
    }

    func closed(_ model: BrowserModel) {
        guard !terminating else { return }
        closedTabs.append(model.url.path)
        if closedTabs.count > 20 { closedTabs.removeFirst() }
        entries[model.id] = nil
        order.removeAll { $0 == model.id }
        scheduleSave()
    }

    func model(withID id: UUID) -> BrowserModel? { entries[id]?.model }

    /// The first open window's model (for the snapshot hook, and for opening folders sent from
    /// other apps when no window is key).
    var firstModel: BrowserModel? { order.lazy.compactMap { self.entries[$0]?.model }.first }

    var hasClosedTabs: Bool { !closedTabs.isEmpty }

    func popClosedTab() -> String? { closedTabs.popLast() }

    // MARK: Session

    /// The first window's spec at launch: the first saved tab (the rest are queued for
    /// `takeRestoreQueue`). Later new windows open the home folder.
    func launchSpec() -> WindowSpec {
        guard !launchSpecTaken else { return WindowSpec() }
        launchSpecTaken = true
        let snapshotRestore = ProcessInfo.processInfo.environment["FILEMANAGER_SNAPSHOT_RESTORE"] != nil
        guard !Self.isSnapshotRun || snapshotRestore, UserDefaults.standard.object(forKey: SettingsKey.reopenSession) as? Bool ?? true,
            let data = UserDefaults.standard.data(forKey: Self.sessionKey),
            let saved = try? JSONDecoder().decode(SessionState.self, from: data)
        else { return WindowSpec() }
        let session = saved.restorable { FileManager.default.fileExists(atPath: $0) }
        var specs: [WindowSpec] = []
        for window in session.windows {
            let first = WindowSpec(path: window.tabs[0], select: window.selected == 0)
            specs.append(first)
            for (index, path) in window.tabs.enumerated().dropFirst() {
                specs.append(WindowSpec(path: path, tabParent: first.id, select: index == window.selected))
            }
        }
        guard let first = specs.first else { return WindowSpec() }
        restoreQueue = Array(specs.dropFirst())
        return first
    }

    /// Folders sent from other apps (Open With, the Dock icon, the Service, `open -a`): each opens
    /// in a new window; a file opens its folder with the file selected. Before any window is up
    /// (the app was launched to open them) they wait for the first window.
    func openFromElsewhere(_ urls: [URL]) {
        let specs = urls.map { url -> WindowSpec in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            return isFolder.boolValue
                ? WindowSpec(path: url.path)
                : WindowSpec(path: url.deletingLastPathComponent().path, reveal: url.path)
        }
        if let model = ActiveBrowser.shared.model ?? firstModel {
            for spec in specs { model.requestOpen(spec) }
            NSApp.activate()
        } else {
            restoreQueue += specs
        }
    }

    /// Windows and tabs still to open after the first one, once.
    func takeRestoreQueue() -> [WindowSpec] {
        defer { restoreQueue = [] }
        return restoreQueue
    }

    func scheduleSave() {
        guard !terminating else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { save() }
        }
    }

    /// Called before quitting, while every window is still open.
    func saveForQuit() {
        saveTask?.cancel()
        save()
        terminating = true
    }

    private func save() {
        guard !Self.isSnapshotRun else { return }
        var groups: [ObjectIdentifier: (windows: [NSWindow], selected: NSWindow?)] = [:]
        var groupOrder: [ObjectIdentifier] = []
        var paths: [ObjectIdentifier: String] = [:]
        for id in order {
            guard let model = entries[id]?.model, let window = model.window, window.isVisible else { continue }
            paths[ObjectIdentifier(window)] = model.url.path
            let group = window.tabGroup
            let key = group.map { ObjectIdentifier($0) } ?? ObjectIdentifier(window)
            if groups[key] == nil {
                groups[key] = (group?.windows ?? [window], group?.selectedWindow)
                groupOrder.append(key)
            }
        }
        let session = SessionState(
            windows: groupOrder.compactMap { key in
                guard let group = groups[key] else { return nil }
                let tabs = group.windows.compactMap { paths[ObjectIdentifier($0)] }
                guard !tabs.isEmpty else { return nil }
                let selected = group.selected.flatMap { group.windows.firstIndex(of: $0) } ?? 0
                return SessionState.Window(tabs: tabs, selected: min(selected, tabs.count - 1))
            })
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
    }
}
