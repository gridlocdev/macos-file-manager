import AppKit
import FileManagerCore
import QuickLookThumbnailing
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// Icon view: a grid of icons and thumbnails (an AppKit collection view, for the same reasons the
/// details list is a table). Shares selection, renaming, the right-click menu, Quick Look and
/// drag and drop with the list.
struct FileIconView: NSViewRepresentable {
    var model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        let grid = FileCollectionView()
        grid.collectionViewLayout = layout
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.allowsEmptySelection = true
        grid.backgroundColors = [.textBackgroundColor]
        grid.register(FileIconItem.self, forItemWithIdentifier: FileIconItem.id)
        grid.register(
            FileGroupHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: FileGroupHeader.id)
        grid.dataSource = context.coordinator
        grid.delegate = context.coordinator
        grid.setAccessibilityLabel("Files")
        context.coordinator.configure(grid)

        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.grid = grid
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let grid = coordinator.grid else { return }
        let version = model.listingVersion
        let selection = model.selection
        let reveal = model.revealAfterLoad
        let focusRequest = model.listFocusRequest
        let iconSize = CGFloat(model.view.iconSize)
        let grouped = model.view.groupBy != .none
        let renameRequest = model.renameRequest
        let quickLookRequest = model.quickLookRequest
        let contextMenuRequest = model.contextMenuRequest
        let cut = Clipboard.shared.cutURLs

        let sizeChanged = iconSize != coordinator.iconSize
        if sizeChanged, let layout = grid.collectionViewLayout as? NSCollectionViewFlowLayout {
            coordinator.iconSize = iconSize
            layout.itemSize = FileIconItem.size(for: iconSize)
        }
        if let layout = grid.collectionViewLayout as? NSCollectionViewFlowLayout {
            let header = grouped ? NSSize(width: 0, height: 30) : .zero
            if layout.headerReferenceSize != header { layout.headerReferenceSize = header }
        }
        if version != coordinator.version || cut != coordinator.cut || sizeChanged, !coordinator.rename.isActive {
            coordinator.reload(scrollToTop: reveal == nil && version != coordinator.version)
        }
        coordinator.applySelection(selection)
        if let reveal, let path = coordinator.indexPath(of: reveal) {
            grid.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
            DispatchQueue.main.async { model.didReveal() }
        }
        if focusRequest != coordinator.focusRequest {
            coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { grid.window?.makeFirstResponder(grid) }
        }
        if quickLookRequest != coordinator.quickLookRequest {
            coordinator.quickLookRequest = quickLookRequest
            grid.quickLook.toggle()
        }
        if contextMenuRequest != coordinator.contextMenuRequest {
            coordinator.contextMenuRequest = contextMenuRequest
            DispatchQueue.main.async { coordinator.showContextMenuFromKeyboard() }
        }
        if renameRequest != coordinator.renameRequest {
            coordinator.renameRequest = renameRequest
            if let target = model.renameTarget {
                DispatchQueue.main.async { coordinator.beginRename(target) }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        let model: BrowserModel
        weak var grid: FileCollectionView?
        /// One section per group (one section when not grouping).
        var sections: [(title: String, items: [FileItem])] = []
        var version = -1
        var cut: Set<URL> = []
        var iconSize: CGFloat = 0
        var focusRequest = 0
        var renameRequest = 0
        var quickLookRequest = 0
        var contextMenuRequest = 0
        var isUpdating = false
        let rename: InlineRename
        let contextMenu: FileContextMenu
        let thumbnails = ThumbnailCache()

        init(model: BrowserModel) {
            self.model = model
            rename = InlineRename(model: model)
            contextMenu = FileContextMenu(model: model)
            super.init()
            rename.finished = { [weak self] in self?.renameFinished() }
        }

        func item(_ path: IndexPath) -> FileItem? {
            guard sections.indices.contains(path.section), sections[path.section].items.indices.contains(path.item)
            else { return nil }
            return sections[path.section].items[path.item]
        }

        func indexPath(of url: URL) -> IndexPath? {
            for (s, section) in sections.enumerated() {
                if let i = section.items.firstIndex(where: { $0.url == url }) { return IndexPath(item: i, section: s) }
            }
            return nil
        }

        func reload(scrollToTop: Bool) {
            guard let grid else { return }
            version = model.listingVersion
            cut = Clipboard.shared.cutURLs
            var built: [(title: String, items: [FileItem])] = []
            for row in model.rows {
                switch row {
                case .header(let title, _): built.append((title, []))
                case .item(let item):
                    if built.isEmpty { built.append(("", [])) }
                    built[built.count - 1].items.append(item)
                }
            }
            sections = built
            isUpdating = true
            grid.reloadData()
            isUpdating = false
            if scrollToTop { grid.scroll(.zero) }
        }

        func applySelection(_ selection: Set<URL>) {
            guard let grid else { return }
            var paths = Set<IndexPath>()
            for (s, section) in sections.enumerated() {
                for (i, item) in section.items.enumerated() where selection.contains(item.url) {
                    paths.insert(IndexPath(item: i, section: s))
                }
            }
            guard paths != grid.selectionIndexPaths else { return }
            isUpdating = true
            grid.selectionIndexPaths = paths
            isUpdating = false
        }

        private func selectionChanged() {
            guard !isUpdating, let grid else { return }
            model.selection = Set(grid.selectionIndexPaths.compactMap { item($0)?.url })
            grid.quickLook.selectionChanged()
        }

        // MARK: Data source

        func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            sections[section].items.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath)
            -> NSCollectionViewItem
        {
            let cell = collectionView.makeItem(withIdentifier: FileIconItem.id, for: indexPath)
            guard let cell = cell as? FileIconItem, let item = item(indexPath) else { return cell }
            cell.show(item, iconSize: iconSize, dimmed: cut.contains(item.url) ? 0.45 : item.isHidden ? 0.55 : 1)
            cell.imageView?.image = thumbnails.image(for: item, size: iconSize) { [weak cell] image in
                // Still showing the same item once the thumbnail arrives?
                guard let cell, cell.url == item.url else { return }
                cell.imageView?.image = image
            }
            return cell
        }

        func collectionView(
            _ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
            at indexPath: IndexPath
        ) -> NSView {
            let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: FileGroupHeader.id, for: indexPath)
            if let header = view as? FileGroupHeader, sections.indices.contains(indexPath.section) {
                let section = sections[indexPath.section]
                header.show(section.title, count: section.items.count)
            }
            return view
        }

        // MARK: Selection

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            selectionChanged()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            selectionChanged()
        }

        // MARK: Dragging out

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent)
            -> Bool
        {
            !rename.isActive
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath)
            -> (any NSPasteboardWriting)?
        {
            item(indexPath)?.url as NSURL?
        }

        // MARK: Dropping in

        func collectionView(
            _ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            let sources = FileDrop.fileURLs(draggingInfo)
            guard !sources.isEmpty else { return [] }
            // Onto a folder: into it. Anywhere else: into the folder being shown.
            if proposedDropOperation.pointee == .on, let target = item(proposedDropIndexPath.pointee as IndexPath),
                target.isFolder
            {
                let operation = FileDrop.operation(sources, into: target.url)
                if operation != .none { return FileDrop.dragOperation(operation) }
            }
            proposedDropOperation.pointee = .before
            return FileDrop.dragOperation(FileDrop.operation(sources, into: model.url))
        }

        func collectionView(
            _ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo, indexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            let sources = FileDrop.fileURLs(draggingInfo)
            let target = dropOperation == .on ? item(indexPath) : nil
            let folder = target?.isFolder == true ? target!.url : model.url
            let operation = FileDrop.operation(sources, into: folder)
            guard operation != .none else { return false }
            model.drop(sources, into: folder, operation: operation)
            return true
        }

        // MARK: Interactions

        func configure(_ grid: FileCollectionView) {
            grid.registerForDraggedTypes([.fileURL])
            grid.setDraggingSourceOperationMask([.copy, .move, .generic, .delete], forLocal: false)
            grid.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
            grid.itemAt = { [unowned self] path in item(path) }
            grid.open = { [unowned self] url in model.open([url]) }
            grid.openInNewTab = { [unowned self] url in model.openInNewTabs([url]) }
            grid.zoom = { [unowned self] zoomIn in model.perform(zoomIn ? .zoomIn : .zoomOut) }
            grid.typeSelect = { [unowned self] prefix in typeSelect(prefix) }
            grid.onFocus = { [unowned self] in model.onFocused?() }
            grid.quickLook.view = grid
            grid.quickLook.urls = { [unowned self] in model.selectedURLs }
            grid.quickLook.frameOnScreen = { [unowned self, unowned grid] url in
                guard let window = grid.window, let path = indexPath(of: url),
                    let cell = grid.item(at: path) as? FileIconItem, let image = cell.imageView
                else { return nil }
                return window.convertToScreen(image.convert(image.bounds, to: nil))
            }
            contextMenu.clickedItem = { [unowned self, unowned grid] in grid.clickedIndexPath.flatMap { item($0)?.url } }
            contextMenu.select = { [unowned self, unowned grid] url in
                grid.selectionIndexPaths = url.flatMap { indexPath(of: $0) }.map { [$0] } ?? []
                selectionChanged()
            }
            grid.menu = contextMenu.menu
        }

        /// Typing the start of a name selects the first item that starts with it.
        private func typeSelect(_ prefix: String) {
            guard let grid,
                let match = model.items.first(where: { $0.name.lowercased().hasPrefix(prefix.lowercased()) }),
                let path = indexPath(of: match.url)
            else { return }
            grid.selectionIndexPaths = [path]
            selectionChanged()
            grid.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
        }

        func beginRename(_ url: URL) {
            guard let grid, !rename.isActive, let path = indexPath(of: url), let item = item(path) else { return }
            grid.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
            grid.selectionIndexPaths = [path]
            selectionChanged()
            guard let cell = grid.item(at: path) as? FileIconItem, let field = cell.textField else { return }
            field.isBordered = true
            field.drawsBackground = true
            rename.begin(url, field: field, isFolder: item.isFolder)
        }

        private func renameFinished() {
            guard let grid else { return }
            for cell in grid.visibleItems() {
                cell.textField?.isBordered = false
                cell.textField?.drawsBackground = false
            }
            if version != model.listingVersion || cut != Clipboard.shared.cutURLs {
                reload(scrollToTop: false)
                applySelection(model.selection)
            }
            grid.window?.makeFirstResponder(grid)
        }

        /// Shift+F10: the menu for the selection, under the first selected item.
        func showContextMenuFromKeyboard() {
            guard let grid else { return }
            let first = grid.selectionIndexPaths.sorted().first
            let point: NSPoint
            if let first, let frame = grid.layoutAttributesForItem(at: first)?.frame {
                point = NSPoint(x: frame.midX, y: frame.maxY)
            } else {
                point = NSPoint(x: 40, y: grid.visibleRect.minY + 30)
            }
            contextMenu.fromKeyboard = true
            contextMenu.menu.popUp(positioning: nil, at: point, in: grid)
            contextMenu.fromKeyboard = false
        }
    }
}

/// The icon grid. Adds double-click (or single-click) to open, middle-click for a new tab,
/// Cmd+scroll to zoom, type-ahead and Quick Look to the collection view.
final class FileCollectionView: NSCollectionView, FileBrowsingView {
    let quickLook = QuickLookSource()
    var itemAt: (IndexPath) -> FileItem? = { _ in nil }
    var open: (URL) -> Void = { _ in }
    var openInNewTab: (URL) -> Void = { _ in }
    var zoom: (Bool) -> Void = { _ in }
    var typeSelect: (String) -> Void = { _ in }
    var onFocus: () -> Void = {}
    /// The item under the pointer for the right-click menu being built.
    private(set) var clickedIndexPath: IndexPath?
    private var typed = ""
    private var lastTyped = Date.distantPast
    private var scrollZoom: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus() }
        return accepted
    }

    private func indexPath(at event: NSEvent) -> IndexPath? {
        indexPathForItem(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        let path = indexPath(at: event)
        super.mouseDown(with: event)
        guard let path, let item = itemAt(path) else { return }
        let plain = event.modifierFlags.isDisjoint(with: [.command, .shift, .option, .control])
        let opens = ViewPreferences.singleClickOpens ? event.clickCount == 1 && plain : event.clickCount == 2
        if opens { open(item.url) }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
        if let path = indexPath(at: event), let item = itemAt(path), item.isFolder { openInNewTab(item.url) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        clickedIndexPath = indexPath(at: event)
        return super.menu(for: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        clickedIndexPath = nil
    }

    /// Cmd+scroll zooms, a step per notch.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return super.scrollWheel(with: event) }
        scrollZoom += event.scrollingDeltaY
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 30 : 1
        if abs(scrollZoom) >= step {
            zoom(scrollZoom > 0)
            scrollZoom = 0
        }
    }

    /// Letters and digits typed without Cmd/Ctrl/Opt select by name; the rest is the grid's.
    override func keyDown(with event: NSEvent) {
        let chars = event.characters ?? ""
        let plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option])
        if plain, !chars.isEmpty, chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).contains($0) }) {
            if Date().timeIntervalSince(lastTyped) > 1 { typed = "" }
            typed += chars
            lastTyped = Date()
            typeSelect(typed)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook.begin(panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook.end(panel) }
    }
}

/// One icon with its name under it (two lines at most).
final class FileIconItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("FileIconItem")
    private(set) var url: URL?
    private let background = NSView()
    private let tagDots = TagDots()
    private let cloudImage = NSImageView()
    private var imageSize: (width: NSLayoutConstraint, height: NSLayoutConstraint)?

    static func size(for iconSize: CGFloat) -> NSSize {
        NSSize(width: max(iconSize + 36, 96), height: iconSize + 46)
    }

    override func loadView() {
        let root = NSView()
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(background)

        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(image)

        let label = NSTextField(wrappingLabelWithString: "")
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)

        // Tags and the iCloud state sit on the icon's bottom-right corner.
        cloudImage.contentTintColor = .secondaryLabelColor
        let badges = NSStackView(views: [tagDots, cloudImage])
        badges.spacing = 3
        badges.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(badges)

        let width = image.widthAnchor.constraint(equalToConstant: 64)
        let height = image.heightAnchor.constraint(equalToConstant: 64)
        imageSize = (width, height)
        NSLayoutConstraint.activate([
            width, height,
            image.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
            image.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            background.topAnchor.constraint(equalTo: image.topAnchor, constant: -3),
            background.bottomAnchor.constraint(equalTo: image.bottomAnchor, constant: 3),
            background.leadingAnchor.constraint(equalTo: image.leadingAnchor, constant: -3),
            background.trailingAnchor.constraint(equalTo: image.trailingAnchor, constant: 3),
            label.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -2),
            badges.trailingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            badges.bottomAnchor.constraint(equalTo: image.bottomAnchor, constant: 2),
        ])
        view = root
        imageView = image
        textField = label
    }

    func show(_ item: FileItem, iconSize: CGFloat, dimmed alpha: CGFloat) {
        url = item.url
        textField?.stringValue = item.name
        textField?.toolTip = item.name
        imageSize?.width.constant = iconSize
        imageSize?.height.constant = iconSize
        view.alphaValue = alpha
        tagDots.tags = item.tags
        tagDots.isHidden = item.tags.isEmpty
        cloudImage.image = CloudBadge.image(item.cloud)
        cloudImage.toolTip = item.cloud?.title
        cloudImage.isHidden = cloudImage.image == nil
        updateHighlight()
    }

    override var isSelected: Bool { didSet { updateHighlight() } }

    private func updateHighlight() {
        background.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor : nil
        textField?.textColor = isSelected ? .controlAccentColor : .labelColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        url = nil
        imageView?.image = nil
    }
}

/// A group's heading in the icon view: "Folders  3".
final class FileGroupHeader: NSView, NSCollectionViewElement {
    static let id = NSUserInterfaceItemIdentifier("FileGroupHeader")
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ title: String, count: Int) {
        let text = NSMutableAttributedString(
            string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        text.append(NSAttributedString(
            string: "   \(count)", attributes: [.font: NSFont.systemFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
        label.attributedStringValue = text
    }
}

/// Thumbnails for the icon view (pictures, movies, PDFs…), made in the background by Quick Look.
/// Until one is ready, or for files without one, the file's icon shows.
@MainActor final class ThumbnailCache {
    private var images: [String: NSImage] = [:]
    private var pending: Set<String> = []
    private let icons = IconCache()

    func image(for item: FileItem, size: CGFloat, ready: @escaping @MainActor (NSImage) -> Void) -> NSImage {
        guard !item.isFolder, item.url.pathExtension.lowercased() != "app" else { return icons.icon(for: item) }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        // Thumbnails are made at the next size up, so zooming between sizes rarely waits.
        let bucket = FolderView.iconSizes.first { CGFloat($0) >= size } ?? Int(size)
        let key = "\(item.url.path)|\(bucket)|\(item.modified?.timeIntervalSince1970 ?? 0)"
        if let cached = images[key] { return cached }
        if !pending.contains(key) {
            pending.insert(key)
            // Pictures, movies and PDFs show their content; other documents (a text file's
            // thumbnail is a white page, invisible on the white grid) get Finder's document icon
            // with a peek at the content.
            let type = UTType(filenameExtension: item.url.pathExtension) ?? .data
            let visual = [UTType.image, .movie, .pdf].contains { type.conforms(to: $0) }
            let request = QLThumbnailGenerator.Request(
                fileAt: item.url, size: CGSize(width: bucket, height: bucket), scale: scale,
                representationTypes: visual ? .thumbnail : .icon)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                let image = thumbnail?.nsImage
                Task { @MainActor in
                    self.pending.remove(key)
                    guard let image else { return }
                    self.images[key] = image
                    ready(image)
                }
            }
        }
        return icons.icon(for: item)
    }
}
