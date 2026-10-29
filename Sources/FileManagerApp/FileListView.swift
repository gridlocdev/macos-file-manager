import AppKit
import FileManagerCore
import SwiftUI
import UniformTypeIdentifiers

/// Details view: an AppKit table, because SwiftUI's Table takes Return/Backspace for itself, has
/// weak type-ahead and slows down on large folders.
struct FileListView: NSViewRepresentable {
    var model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .inset
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowHeight = 22
        for column in FileSort.Column.allCases {
            let tableColumn = NSTableColumn(identifier: .init(column.rawValue))
            tableColumn.title = column.title
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                key: column.rawValue, ascending: column == .name || column == .kind)
            switch column {
            case .name: tableColumn.width = 240; tableColumn.minWidth = 120
            case .modified: tableColumn.width = 170; tableColumn.minWidth = 80
            case .kind: tableColumn.width = 130; tableColumn.minWidth = 60
            case .size: tableColumn.width = 70; tableColumn.minWidth = 50
            }
            table.addTableColumn(tableColumn)
        }
        table.autosaveName = "FileList"
        table.autosaveTableColumns = true
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setAccessibilityLabel("Files")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let table = coordinator.table else { return }
        // Read everything SwiftUI should watch.
        let version = model.listingVersion
        let selection = model.selection
        let reveal = model.revealAfterLoad
        let focusRequest = model.listFocusRequest
        let sort = model.sort

        let descriptor = NSSortDescriptor(key: sort.column.rawValue, ascending: sort.ascending)
        if table.sortDescriptors.first != descriptor {
            coordinator.isUpdating = true
            table.sortDescriptors = [descriptor]
            coordinator.isUpdating = false
        }
        if version != coordinator.version {
            coordinator.version = version
            coordinator.items = model.items
            coordinator.isUpdating = true
            table.reloadData()
            coordinator.isUpdating = false
            if reveal == nil { table.scrollRowToVisible(0) }
        }
        coordinator.applySelection(selection)
        if let reveal, let row = coordinator.items.firstIndex(where: { $0.url == reveal }) {
            table.scrollRowToVisible(row)
            DispatchQueue.main.async { model.didReveal() }
        }
        if focusRequest != coordinator.focusRequest {
            coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { table.window?.makeFirstResponder(table) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let model: BrowserModel
        weak var table: NSTableView?
        var items: [FileItem] = []
        var version = -1
        var focusRequest = 0
        var isUpdating = false
        private let icons = IconCache()

        init(model: BrowserModel) { self.model = model }

        func applySelection(_ selection: Set<URL>) {
            guard let table else { return }
            let rows = IndexSet(items.indices.filter { selection.contains(items[$0].url) })
            guard rows != table.selectedRowIndexes else { return }
            isUpdating = true
            table.selectRowIndexes(rows, byExtendingSelection: false)
            isUpdating = false
        }

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = FileSort.Column(rawValue: tableColumn.identifier.rawValue)
            else { return nil }
            let item = items[row]
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? FileCell
                ?? FileCell(identifier: tableColumn.identifier, withIcon: column == .name)
            cell.alphaValue = item.isHidden ? 0.55 : 1
            switch column {
            case .name:
                cell.textField?.stringValue = item.name
                cell.imageView?.image = icons.icon(for: item)
            case .modified:
                cell.textField?.stringValue = item.modified.map(Self.formatDate) ?? "--"
            case .kind:
                cell.textField?.stringValue = item.kind
            case .size:
                cell.textField?.stringValue = item.size.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? "--"
            }
            cell.textField?.alignment = column == .size ? .right : .left
            cell.textField?.textColor = column == .name ? .labelColor : .secondaryLabelColor
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table else { return }
            model.selection = Set(table.selectedRowIndexes.compactMap {
                $0 < items.count ? items[$0].url : nil
            })
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isUpdating, let descriptor = tableView.sortDescriptors.first,
                let key = descriptor.key, let column = FileSort.Column(rawValue: key)
            else { return }
            model.sort.column = column
            model.sort.ascending = descriptor.ascending
        }

        /// Type-ahead: typing selects the first name that starts with the letters.
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            tableColumn?.identifier.rawValue == FileSort.Column.name.rawValue ? items[row].name : nil
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < items.count else { return }
            model.open([items[row].url])
        }

        private static func formatDate(_ date: Date) -> String {
            date.formatted(date: .abbreviated, time: .shortened)
        }
    }
}

private final class FileCell: NSTableCellView {
    init(identifier: NSUserInterfaceItemIdentifier, withIcon: Bool) {
        super.init(frame: .zero)
        self.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        textField = text
        if withIcon {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            addSubview(image)
            imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            ])
        } else {
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2).isActive = true
        }
        NSLayoutConstraint.activate([
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// Folder and app icons are per item; plain files share one icon per extension.
@MainActor private final class IconCache {
    private var byPath: [String: NSImage] = [:]
    private var byExtension: [String: NSImage] = [:]

    func icon(for item: FileItem) -> NSImage {
        let ext = item.url.pathExtension.lowercased()
        if item.isFolder || ext == "app" || ext.isEmpty {
            if let cached = byPath[item.url.path] { return cached }
            let icon = NSWorkspace.shared.icon(forFile: item.url.path)
            byPath[item.url.path] = icon
            return icon
        }
        if let cached = byExtension[ext] { return cached }
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        byExtension[ext] = icon
        return icon
    }
}
