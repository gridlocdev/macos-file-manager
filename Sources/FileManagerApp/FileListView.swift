import AppKit
import FileManagerCore
import SwiftUI

/// Details view: an AppKit table, because SwiftUI's Table takes Return/Backspace for itself, has
/// weak type-ahead and slows down on large folders.
struct FileListView: NSViewRepresentable {
    var model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTableView()
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
                key: column.rawValue, ascending: [.name, .kind, .ext].contains(column))
            switch column {
            case .name: tableColumn.width = 240; tableColumn.minWidth = 120
            case .modified, .created, .added: tableColumn.width = 170; tableColumn.minWidth = 80
            case .kind: tableColumn.width = 130; tableColumn.minWidth = 60
            case .size: tableColumn.width = 70; tableColumn.minWidth = 50
            case .ext: tableColumn.width = 70; tableColumn.minWidth = 40
            case .permissions: tableColumn.width = 100; tableColumn.minWidth = 80
            case .tags: tableColumn.width = 120; tableColumn.minWidth = 50
            }
            tableColumn.isHidden = !column.isShownByDefault
            table.addTableColumn(tableColumn)
        }
        // Where each result is, while searching subfolders.
        let folderColumn = NSTableColumn(identifier: Coordinator.folderColumn)
        folderColumn.title = "Folder"
        folderColumn.width = 160
        folderColumn.minWidth = 60
        folderColumn.isHidden = true
        table.addTableColumn(folderColumn)
        // Column widths, order and which are shown are remembered.
        table.autosaveName = "FileList"
        table.autosaveTableColumns = true
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.action = #selector(Coordinator.clicked(_:))
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setAccessibilityLabel("Files")
        context.coordinator.configureInteractions(table)

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
        let view = model.view
        let commands = model.takeFileViewCommands()
        let cut = Clipboard.shared.cutURLs
        let showsFolders = model.isSearchingSubfolders
        coordinator.root = model.url
        if let column = table.tableColumn(withIdentifier: Coordinator.folderColumn), column.isHidden == showsFolders {
            column.isHidden = !showsFolders
        }

        let descriptor = NSSortDescriptor(key: view.sortColumn.rawValue, ascending: view.ascending)
        if table.sortDescriptors.first != descriptor {
            coordinator.isUpdating = true
            table.sortDescriptors = [descriptor]
            coordinator.isUpdating = false
        }
        // Zoom: bigger icons need taller rows.
        let iconSize = CGFloat(view.listIconSize)
        let sizeChanged = iconSize != coordinator.iconSize
        if sizeChanged {
            coordinator.iconSize = iconSize
            table.rowHeight = iconSize + 6
        }
        // While a name is being edited a reload would throw the edit away; it catches up after.
        if version != coordinator.version || cut != coordinator.cut || sizeChanged, !coordinator.rename.isActive {
            // Only a new folder starts at the top; a refresh of this one keeps the scroll position.
            coordinator.reload(scrollToTop: reveal == nil && model.url != coordinator.listedFolder)
        }
        coordinator.applySelection(selection)
        if let reveal, let row = coordinator.row(of: reveal) {
            table.scrollRowToVisible(row)
            Task { model.didReveal() }
        }
        // Focus, the menu and rename wait until this update is done.
        var later: [PaneCommand] = []
        for command in commands {
            if case .quickLook = command { table.quickLook.toggle() } else { later.append(command) }
        }
        if !later.isEmpty {
            Task {
                for command in later {
                    switch command {
                    case .focusList: table.window?.makeFirstResponder(table)
                    case .contextMenu: coordinator.showContextMenuFromKeyboard()
                    case .rename(let target): coordinator.beginRename(target)
                    default: break
                    }
                }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        static let folderColumn = NSUserInterfaceItemIdentifier("folder")
        let model: BrowserModel
        weak var table: FileTableView?
        /// Group headings and items, as shown.
        var rows: [ListRow] = []
        var version = -1
        /// The folder whose listing is shown.
        var listedFolder: URL?
        var cut: Set<URL> = []
        var iconSize: CGFloat = 16
        var root = URL(filePath: "/")
        var isUpdating = false
        let rename: InlineRename
        let contextMenu: FileContextMenu
        private let icons = IconCache()

        init(model: BrowserModel) {
            self.model = model
            rename = InlineRename(model: model)
            contextMenu = FileContextMenu(model: model)
            super.init()
            rename.finished = { [weak self] in self?.renameFinished() }
        }

        func item(_ row: Int) -> FileItem? { rows.indices.contains(row) ? rows[row].item : nil }

        func row(of url: URL) -> Int? { rows.firstIndex { $0.item?.url == url } }

        func reload(scrollToTop: Bool) {
            guard let table else { return }
            version = model.listingVersion
            listedFolder = model.url
            cut = Clipboard.shared.cutURLs
            rows = model.rows
            isUpdating = true
            table.reloadData()
            isUpdating = false
            if scrollToTop { table.scrollRowToVisible(0) }
        }

        func applySelection(_ selection: Set<URL>) {
            guard let table else { return }
            let indexes = IndexSet(rows.indices.filter { rows[$0].item.map { selection.contains($0.url) } ?? false })
            guard indexes != table.selectedRowIndexes else { return }
            isUpdating = true
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            isUpdating = false
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows[row].item == nil }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].item != nil }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            rows[row].item == nil ? 28 : tableView.rowHeight
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let item = rows[row].item else {
                guard case .header(let title, let count) = rows[row] else { return nil }
                return headerCell(tableView, title: title, count: count)
            }
            if tableColumn?.identifier == Self.folderColumn { return folderCell(tableView, item: item) }
            guard let tableColumn, let column = FileSort.Column(rawValue: tableColumn.identifier.rawValue)
            else { return nil }
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? FileCell
                ?? FileCell(identifier: tableColumn.identifier, withIcon: column == .name)
            // Hidden files and cut items are dimmed, as in Explorer.
            cell.alphaValue = cut.contains(item.url) ? 0.45 : item.isHidden ? 0.55 : 1
            cell.textField?.stringValue = FileFormat.value(item, column)
            if column == .name {
                cell.imageView?.image = icons.icon(for: item)
                cell.iconSize = iconSize
                cell.showBadges(tags: item.tags, cloud: item.cloud)
            }
            cell.textField?.alignment = column == .size ? .right : .left
            cell.textField?.textColor = column == .name ? .labelColor : .secondaryLabelColor
            cell.textField?.font = column == .permissions ? .monospacedSystemFont(ofSize: 0, weight: .regular) : .systemFont(ofSize: 0)
            return cell
        }

        /// "Folders  3", spanning the whole row.
        private func headerCell(_ tableView: NSTableView, title: String, count: Int) -> NSView {
            let id = NSUserInterfaceItemIdentifier("group")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? FileCell
                ?? FileCell(identifier: id, withIcon: false)
            let text = NSMutableAttributedString(
                string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
            text.append(NSAttributedString(
                string: "   \(count)", attributes: [.font: NSFont.systemFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
            cell.textField?.attributedStringValue = text
            cell.alphaValue = 1
            return cell
        }

        /// The result's folder relative to the one being searched ("Photos/2024").
        private func folderCell(_ tableView: NSTableView, item: FileItem) -> NSView {
            let cell = tableView.makeView(withIdentifier: Self.folderColumn, owner: nil) as? FileCell
                ?? FileCell(identifier: Self.folderColumn, withIcon: false)
            let folder = item.url.deletingLastPathComponent().path
            let rootPath = root.path == "/" ? "" : root.path
            let relative = folder.hasPrefix(rootPath + "/") ? String(folder.dropFirst(rootPath.count + 1)) : ""
            cell.textField?.stringValue = relative.isEmpty ? FileManager.default.displayName(atPath: root.path) : relative
            cell.textField?.textColor = .secondaryLabelColor
            cell.toolTip = folder
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table else { return }
            model.selection = Set(table.selectedRowIndexes.compactMap { item($0)?.url })
            table.quickLook.selectionChanged()
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isUpdating, let descriptor = tableView.sortDescriptors.first,
                let key = descriptor.key, let column = FileSort.Column(rawValue: key)
            else { return }
            model.view.sortColumn = column
            model.view.ascending = descriptor.ascending
        }

        /// Type-ahead: typing selects the first name that starts with the letters.
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            tableColumn?.identifier.rawValue == FileSort.Column.name.rawValue ? item(row)?.name : nil
        }

        // MARK: Columns

        /// Right-click the column headings: choose which columns show.
        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let table else { return }
            menu.removeAllItems()
            for column in FileSort.Column.allCases where column != .name {
                guard let tableColumn = table.tableColumn(withIdentifier: .init(column.rawValue)) else { continue }
                let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = column.rawValue
                item.state = tableColumn.isHidden ? .off : .on
                menu.addItem(item)
            }
        }

        @objc func toggleColumn(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String,
                let column = table?.tableColumn(withIdentifier: .init(raw))
            else { return }
            column.isHidden.toggle()
        }

        // MARK: Rename

        /// Edits the name in place, with the name selected without its extension.
        func beginRename(_ url: URL) {
            guard let table, !rename.isActive, let row = row(of: url), let item = item(row),
                let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == FileSort.Column.name.rawValue }),
                let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView,
                let field = cell.textField
            else { return }
            table.scrollRowToVisible(row)
            table.selectRowIndexes([row], byExtendingSelection: false)
            rename.begin(url, field: field, isFolder: item.isFolder)
        }

        private func renameFinished() {
            guard let table else { return }
            // Catch up on any listing changes held back while editing.
            if version != model.listingVersion || cut != Clipboard.shared.cutURLs {
                reload(scrollToTop: false)
                applySelection(model.selection)
            }
            table.window?.makeFirstResponder(table)
        }

        // MARK: Opening

        /// With "Open items with a single click" on, a plain click opens.
        @objc func clicked(_ sender: NSTableView) {
            guard Preferences.standard.singleClickOpen, NSEvent.modifierFlags.isDisjoint(with: [.command, .shift, .option, .control]),
                let item = item(sender.clickedRow)
            else { return }
            model.open([item.url])
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            guard !Preferences.standard.singleClickOpen, let item = item(sender.clickedRow) else { return }
            model.open([item.url])
        }
    }
}

final class FileCell: NSTableCellView {
    private var iconWidth: NSLayoutConstraint?
    private var iconHeight: NSLayoutConstraint?
    /// Tag dots and the iCloud symbol, after the name.
    private var badges: NSStackView?
    private let tagDots = TagDots()
    private let cloudImage = NSImageView()

    func showBadges(tags: [String], cloud: CloudStatus?) {
        tagDots.tags = tags
        tagDots.isHidden = tags.isEmpty
        cloudImage.image = CloudBadge.image(cloud)
        cloudImage.toolTip = cloud?.title
        cloudImage.isHidden = cloud == nil || cloud == .current
    }

    var iconSize: CGFloat = 16 {
        didSet {
            iconWidth?.constant = iconSize
            iconHeight?.constant = iconSize
        }
    }

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
            image.imageScaling = .scaleProportionallyUpOrDown
            addSubview(image)
            imageView = image
            let width = image.widthAnchor.constraint(equalToConstant: 16)
            let height = image.heightAnchor.constraint(equalToConstant: 16)
            iconWidth = width
            iconHeight = height
            cloudImage.contentTintColor = .secondaryLabelColor
            let stack = NSStackView(views: [tagDots, cloudImage])
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.setContentHuggingPriority(.required, for: .horizontal)
            stack.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(stack)
            badges = stack
            tagDots.isHidden = true
            cloudImage.isHidden = true
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: centerYAnchor),
                width, height,
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 4),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            // The name gives way to the badges, then truncates.
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        } else {
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2).isActive = true
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2).isActive = true
        }
        text.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
