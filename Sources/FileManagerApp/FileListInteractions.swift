import AppKit
import FileManagerCore
import QuickLookUI

/// The file list's table. Besides the usual table behaviour it:
/// - tells `KeyMonitor` the list has focus (Return renames and Delete trashes only then),
/// - opens folders you hover over while dragging (spring-loaded folders),
/// - drives the Quick Look panel,
/// - hands the selection to Services.
final class FileTableView: NSTableView, NSSpringLoadingDestination {
    /// Set by the coordinator.
    var isFolderRow: (Int) -> Bool = { _ in false }
    var openRow: (Int) -> Void = { _ in }
    var previewURLs: () -> [URL] = { [] }
    var rowForURL: (URL) -> Int? = { _ in nil }

    // MARK: Spring-loaded folders

    private func folderRow(under info: any NSDraggingInfo) -> Int? {
        let row = row(at: convert(info.draggingLocation, from: nil))
        return row >= 0 && isFolderRow(row) ? row : nil
    }

    func springLoadingEntered(_ draggingInfo: any NSDraggingInfo) -> NSSpringLoadingOptions {
        folderRow(under: draggingInfo) == nil ? .disabled : .enabled
    }

    func springLoadingUpdated(_ draggingInfo: any NSDraggingInfo) -> NSSpringLoadingOptions {
        folderRow(under: draggingInfo) == nil ? .disabled : .enabled
    }

    func springLoadingActivated(_ activated: Bool, draggingInfo: any NSDraggingInfo) {
        guard activated, let row = folderRow(under: draggingInfo) else { return }
        openRow(row)
    }

    func springLoadingHighlightChanged(_ draggingInfo: any NSDraggingInfo) {}

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    // These come from an NSObject category without main-actor annotations; Quick Look calls
    // them on the main thread.
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            window?.makeFirstResponder(self)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Keeps an open Quick Look panel on the current selection.
    func selectionChangedForQuickLook() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible,
            panel.dataSource === self
        else { return }
        panel.reloadData()
    }

    // MARK: Services

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == .fileURL, returnType == nil, !previewURLs().isEmpty { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }
}

extension FileTableView: @preconcurrency NSServicesMenuRequestor {
    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let urls = previewURLs()
        guard !urls.isEmpty else { return false }
        pboard.clearContents()
        return pboard.writeObjects(urls as [NSURL])
    }
}

extension FileTableView: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs().count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs()[index] as NSURL
    }

    /// Up/Down in the panel move through the list, as in Finder; Space closes it. Everything
    /// else (Esc, Left/Right within a multi-page preview) is the panel's.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        switch event.keyCode {
        case 125, 126:
            keyDown(with: event)
            return true
        case 49:
            panel.orderOut(nil)
            return true
        default:
            return false
        }
    }

    /// Zooms the preview out of the item's icon.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let url = item.previewItemURL ?? nil, let window, let row = rowForURL(url.normalized)
        else { return .zero }
        var rect = frameOfCell(atColumn: 0, row: row)
        rect.size.width = rect.height
        return window.convertToScreen(convert(rect, to: nil))
    }
}

// MARK: - Drag and drop, right-click menu

extension FileListView.Coordinator: NSMenuDelegate {
    func configureInteractions(_ table: FileTableView) {
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move, .generic, .delete], forLocal: false)
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.draggingDestinationFeedbackStyle = .regular
        table.isFolderRow = { [unowned self] row in row < items.count && items[row].isFolder }
        table.openRow = { [unowned self] row in
            guard row < items.count else { return }
            model.navigate(to: items[row].url)
        }
        table.previewURLs = { [unowned self] in model.selectedURLs }
        table.rowForURL = { [unowned self] url in items.firstIndex { $0.url == url } }
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
    }

    // MARK: Dragging out

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row < items.count else { return nil }
        return items[row].url as NSURL
    }

    // MARK: Dropping in

    func tableView(
        _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        let sources = Self.fileURLs(info)
        guard !sources.isEmpty else { return [] }
        // Onto a folder row: into that folder. Anywhere else: into the folder being shown.
        if dropOperation == .on, row >= 0, row < items.count, items[row].isFolder {
            let operation = Self.operation(sources, into: items[row].url)
            if operation != .none { return Self.dragOperation(operation) }
        }
        tableView.setDropRow(-1, dropOperation: .on)
        return Self.dragOperation(Self.operation(sources, into: model.url))
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let sources = Self.fileURLs(info)
        let folder = row >= 0 && row < items.count && items[row].isFolder ? items[row].url : model.url
        let operation = Self.operation(sources, into: folder)
        guard operation != .none else { return false }
        model.drop(sources, into: folder, operation: operation)
        return true
    }

    static func fileURLs(_ info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
    }

    /// Move on the same disk, copy across disks; Opt copies, Cmd moves.
    static func operation(_ sources: [URL], into folder: URL) -> DropRules.Operation {
        let flags = NSEvent.modifierFlags
        return DropRules.operation(
            dropping: sources, into: folder, option: flags.contains(.option), command: flags.contains(.command),
            sameVolume: sameVolume)
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        func volume(_ url: URL) -> NSObject? {
            (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        }
        guard let left = volume(a), let right = volume(b) else { return false }
        return left.isEqual(right)
    }

    static func dragOperation(_ operation: DropRules.Operation) -> NSDragOperation {
        switch operation {
        case .copy: .copy
        case .move: .move
        case .none: []
        }
    }

    // MARK: Right-click menu

    /// Shift+F10: the menu for the selection, under the first selected row.
    func showContextMenuFromKeyboard() {
        guard let table, let menu = table.menu else { return }
        menuFromKeyboard = true
        let row = table.selectedRowIndexes.first ?? -1
        let point =
            row >= 0
            ? NSPoint(x: table.frameOfCell(atColumn: 0, row: row).minX + 40, y: table.rect(ofRow: row).maxY)
            : NSPoint(x: 40, y: table.visibleRect.minY + 30)
        menu.popUp(positioning: nil, at: point, in: table)
        menuFromKeyboard = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let table else { return }
        menu.removeAllItems()
        let clicked = table.clickedRow
        if clicked >= 0, clicked < items.count {
            // Right-clicking outside the selection selects that item, as in Finder and Explorer.
            if !table.selectedRowIndexes.contains(clicked) {
                table.selectRowIndexes([clicked], byExtendingSelection: false)
            }
            buildItemMenu(menu)
        } else if menuFromKeyboard, !model.selection.isEmpty {
            buildItemMenu(menu)
        } else {
            if !menuFromKeyboard { table.deselectAll(nil) }
            buildFolderMenu(menu)
        }
    }

    private func buildItemMenu(_ menu: NSMenu) {
        let urls = model.selectedURLs
        guard let first = urls.first else { return }
        let selected = items.filter { model.selection.contains($0.url) }
        add(.open, to: menu)
        menu.addItem(openWithItem(for: urls, first: first))
        add(.quickLook, to: menu)
        menu.addItem(.separator())
        add(.cut, to: menu)
        add(.copy, to: menu)
        add(.duplicate, to: menu)
        add(.rename, to: menu)
        menu.addItem(.separator())
        add(.copyPath, to: menu)
        add(.getInfo, to: menu)
        if selected.count == 1, selected[0].isFolder {
            let item = NSMenuItem(title: Action.openTerminal.title, action: #selector(openTerminalInFolder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = first
            menu.addItem(item)
        }
        add(.showInFinder, to: menu)
        menu.addItem(.separator())
        if model.isTrashFolder {
            add(.putBack, to: menu)
        } else {
            add(.moveToTrash, to: menu)
        }
        menu.addItem(.separator())
        menu.addItem(NSSharingServicePicker(items: urls).standardShareMenuItem)
    }

    private func buildFolderMenu(_ menu: NSMenu) {
        add(.newFolder, to: menu)
        add(.newTextFile, to: menu)
        add(.paste, to: menu)
        menu.addItem(.separator())
        let sort = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for column in FileSort.Column.allCases {
            let item = NSMenuItem(title: column.title, action: #selector(sortBy(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.rawValue
            item.state = model.sort.column == column ? .on : .off
            sortMenu.addItem(item)
        }
        sort.submenu = sortMenu
        menu.addItem(sort)
        let hidden = add(.toggleHiddenFiles, to: menu)
        hidden.state = model.showHiddenFiles ? .on : .off
        add(.refresh, to: menu)
        menu.addItem(.separator())
        add(.openTerminal, to: menu)
        add(.copyPath, to: menu)
        add(.getInfo, to: menu)
        add(.showInFinder, to: menu)
    }

    @discardableResult
    private func add(_ action: Action, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        item.isEnabled = model.canPerform(action)
        menu.addItem(item)
        return item
    }

    /// Open With: apps that can open the first item, the default first.
    private func openWithItem(for urls: [URL], first: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: first)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        if let defaultApp {
            apps.removeAll { $0 == defaultApp }
            apps.insert(defaultApp, at: 0)
        }
        var seen = Set<String>()
        for app in apps {
            let name = FileManager.default.displayName(atPath: app.path)
            guard seen.insert(name).inserted else { continue }
            let entry = NSMenuItem(
                title: app == defaultApp ? "\(name) (default)" : name, action: #selector(openWith(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
            if app == defaultApp, apps.count > 1 { submenu.addItem(.separator()) }
        }
        submenu.addItem(.separator())
        let other = NSMenuItem(title: "Other…", action: #selector(openWithOther(_:)), keyEquivalent: "")
        other.target = self
        submenu.addItem(other)
        item.submenu = submenu
        return item
    }

    @objc func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = Action(rawValue: raw) else { return }
        model.perform(action)
    }

    @objc func sortBy(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let column = FileSort.Column(rawValue: raw) else { return }
        model.sort.column = column
    }

    @objc func openTerminalInFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        TerminalLauncher.open(folder)
    }

    @objc func openWith(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(model.selectedURLs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func openWithOther(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Open"
        let urls = model.selectedURLs
        guard panel.runModal() == .OK, let app = panel.url else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
