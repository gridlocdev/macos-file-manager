import AppKit
import FileManagerCore
import QuickLookUI

/// The file list's table. Besides the usual table behaviour it:
/// - tells `KeyMonitor` the list has focus (Return renames and Delete trashes only then),
/// - opens folders you hover over while dragging (spring-loaded folders),
/// - drives the Quick Look panel,
/// - hands the selection to Services.
final class FileTableView: NSTableView, NSSpringLoadingDestination, FileBrowsingView {
    let quickLook = QuickLookSource()
    /// Set by the coordinator.
    var isFolderRow: (Int) -> Bool = { _ in false }
    var openRow: (Int) -> Void = { _ in }
    var middleClickRow: (Int) -> Void = { _ in }
    var onFocus: () -> Void = {}

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus() }
        return accepted
    }

    /// Middle-click a folder: open it in a new tab, like a browser.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { middleClickRow(row) }
    }

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
        MainActor.assumeIsolated { quickLook.begin(panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook.end(panel) }
    }

    // MARK: Services

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == .fileURL, returnType == nil, !quickLook.urls().isEmpty { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }
}

extension FileTableView: @preconcurrency NSServicesMenuRequestor {
    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let urls = quickLook.urls()
        guard !urls.isEmpty else { return false }
        pboard.clearContents()
        return pboard.writeObjects(urls as [NSURL])
    }
}

// MARK: - Drag and drop, right-click menu

extension FileListView.Coordinator {
    func configureInteractions(_ table: FileTableView) {
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move, .generic, .delete], forLocal: false)
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.draggingDestinationFeedbackStyle = .regular
        table.isFolderRow = { [unowned self] row in item(row)?.isFolder ?? false }
        table.openRow = { [unowned self] row in
            if let item = item(row) { model.navigate(to: item.url) }
        }
        table.middleClickRow = { [unowned self] row in
            guard let item = item(row), item.isFolder else { return }
            model.openInNewTabs([item.url])
        }
        table.onFocus = { [unowned self] in model.onFocused?() }
        table.quickLook.view = table
        table.quickLook.urls = { [unowned self] in model.selectedURLs }
        table.quickLook.frameOnScreen = { [unowned self, unowned table] url in
            guard let window = table.window, let row = row(of: url) else { return nil }
            var rect = table.frameOfCell(atColumn: 0, row: row)
            rect.size.width = rect.height
            return window.convertToScreen(table.convert(rect, to: nil))
        }

        contextMenu.clickedItem = { [unowned self, unowned table] in item(table.clickedRow)?.url }
        contextMenu.select = { [unowned self, unowned table] url in
            if let url, let row = row(of: url) {
                table.selectRowIndexes([row], byExtendingSelection: false)
            } else {
                table.deselectAll(nil)
            }
        }
        table.menu = contextMenu.menu

        // Right-click the headings to choose columns.
        let headerMenu = NSMenu()
        headerMenu.delegate = self
        table.headerView?.menu = headerMenu
    }

    // MARK: Dragging out

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        item(row)?.url as NSURL?
    }

    // MARK: Dropping in

    func tableView(
        _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        let sources = FileDrop.fileURLs(info)
        guard !sources.isEmpty else { return [] }
        // Onto a folder row: into that folder. Anywhere else: into the folder being shown.
        if dropOperation == .on, let item = item(row), item.isFolder {
            let operation = FileDrop.operation(sources, into: item.url)
            if operation != .none { return FileDrop.dragOperation(operation) }
        }
        tableView.setDropRow(-1, dropOperation: .on)
        return FileDrop.dragOperation(FileDrop.operation(sources, into: model.url))
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let sources = FileDrop.fileURLs(info)
        let target = item(row)
        let folder = target?.isFolder == true ? target!.url : model.url
        let operation = FileDrop.operation(sources, into: folder)
        guard operation != .none else { return false }
        model.drop(sources, into: folder, operation: operation)
        return true
    }

    // MARK: Right-click menu

    /// Shift+F10: the menu for the selection, under the first selected row.
    func showContextMenuFromKeyboard() {
        guard let table else { return }
        let row = table.selectedRowIndexes.first ?? -1
        let point =
            row >= 0
            ? NSPoint(x: table.frameOfCell(atColumn: 0, row: row).minX + 40, y: table.rect(ofRow: row).maxY)
            : NSPoint(x: 40, y: table.visibleRect.minY + 30)
        contextMenu.fromKeyboard = true
        contextMenu.menu.popUp(positioning: nil, at: point, in: table)
        contextMenu.fromKeyboard = false
    }
}
