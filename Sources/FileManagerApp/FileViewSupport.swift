import AppKit
import FileManagerCore
import UniformTypeIdentifiers

/// Renaming in place, in the details list or the icon view: the name is selected without its
/// extension, Return or clicking away saves, Esc puts it back.
@MainActor final class InlineRename: NSObject, NSTextFieldDelegate {
    let model: BrowserModel
    /// Called after editing ends either way, so the view can catch up and take focus back.
    var finished: () -> Void = {}
    private var session: (url: URL, field: NSTextField, original: String)?

    var isActive: Bool { session != nil }

    init(model: BrowserModel) { self.model = model }

    func begin(_ url: URL, field: NSTextField, isFolder: Bool) {
        guard session == nil else { return }
        let name = url.lastPathComponent
        session = (url, field, field.stringValue)
        // Edit the real file name, even if the view hides the extension.
        field.stringValue = name
        field.isEditable = true
        field.isSelectable = true
        field.delegate = self
        field.window?.makeFirstResponder(field)
        let length = FileNaming.baseLength(of: name, isFolder: isFolder)
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), let session else { return false }
        self.session = nil
        session.field.abortEditing()
        end(session.field, restoring: session.original)
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let session, let field = notification.object as? NSTextField, field === session.field else { return }
        self.session = nil
        let newName = field.stringValue
        end(field, restoring: session.original)
        model.commitRename(session.url, to: newName)
    }

    private func end(_ field: NSTextField, restoring original: String) {
        field.isEditable = false
        field.isSelectable = false
        field.delegate = nil
        field.stringValue = original
        finished()
    }
}

/// Folder and app icons are per item; plain files share one icon per type. One cache for every
/// pane. A per-item icon is read from disk in the background (slow on a network share): until it
/// arrives the generic folder, app or document icon shows, and `ready` gets the real one.
@MainActor final class IconCache {
    static let shared = IconCache()

    private let byPath: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 5000
        return cache
    }()
    private var byType: [String: NSImage] = [:]
    private var waiting: [String: [@MainActor (NSImage) -> Void]] = [:]

    func icon(for item: FileItem, ready: (@MainActor (NSImage) -> Void)? = nil) -> NSImage {
        let ext = item.url.pathExtension.lowercased()
        guard item.isFolder || ext == "app" || ext.isEmpty else {
            return typeIcon(ext, UTType(filenameExtension: ext) ?? .data)
        }
        let path = item.url.path
        if let cached = byPath.object(forKey: path as NSString) { return cached }
        let placeholder =
            item.isFolder ? typeIcon("/folder", .folder) : ext == "app" ? typeIcon("/app", .application) : typeIcon("", .data)
        let first = waiting[path] == nil
        waiting[path, default: []] += ready.map { [$0] } ?? []
        if first {
            Task.detached(priority: .utility) {
                let icon = UncheckedImage(NSWorkspace.shared.icon(forFile: path))
                await self.loaded(icon.image, for: path)
            }
        }
        return placeholder
    }

    private func loaded(_ icon: NSImage, for path: String) {
        byPath.setObject(icon, forKey: path as NSString)
        for ready in waiting.removeValue(forKey: path) ?? [] { ready(icon) }
    }

    private func typeIcon(_ key: String, _ type: UTType) -> NSImage {
        if let cached = byType[key] { return cached }
        let icon = NSWorkspace.shared.icon(for: type)
        byType[key] = icon
        return icon
    }
}

/// An image handed from the background to the main actor once, and not touched again there.
private struct UncheckedImage: @unchecked Sendable {
    let image: NSImage
    init(_ image: NSImage) { self.image = image }
}

/// What a drop does, for the list, the icon view and the sidebar.
@MainActor enum FileDrop {
    static func fileURLs(_ info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
    }

    /// Move on the same disk, copy across disks; Opt copies, Cmd moves.
    static func operation(_ sources: [URL], into folder: URL) -> DropRules.Operation {
        let flags = NSEvent.modifierFlags
        return DropRules.operation(
            // The real path, so a symlinked folder on the way up is seen through.
            dropping: sources, into: folder.realPath, option: flags.contains(.option), command: flags.contains(.command),
            sameVolume: sameVolume, sameItem: { $0.isSameItem(as: $1) })
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
}

enum FileFormat {
    static func date(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "--"
    }

    static func size(_ size: Int64?) -> String {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--"
    }

    /// The text for a details column.
    static func value(_ item: FileItem, _ column: FileSort.Column) -> String {
        switch column {
        case .name: item.name
        case .modified: date(item.modified)
        case .created: date(item.created)
        case .added: date(item.added)
        case .kind: item.kind
        case .size: size(item.size)
        case .ext: item.fileExtension
        case .permissions: item.permissions.map { Permissions.symbolic($0, isFolder: item.isFolder) } ?? "--"
        case .tags: item.tags.joined(separator: ", ")
        }
    }
}

/// Finder-style overlapping coloured dots for an item's tags (tags without a standard colour
/// are grey). At most three show, as in Finder.
final class TagDots: NSView {
    var tags: [String] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
            toolTip = tags.joined(separator: ", ")
        }
    }

    private static let size: CGFloat = 10
    private var shown: [String] { Array(tags.prefix(3)) }

    override var intrinsicContentSize: NSSize {
        NSSize(width: shown.isEmpty ? 0 : Self.size + CGFloat(shown.count - 1) * 5, height: Self.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, tag) in shown.enumerated().reversed() {
            let rect = NSRect(x: CGFloat(i) * 5, y: (bounds.height - Self.size) / 2, width: Self.size, height: Self.size)
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            Self.color(for: tag).setFill()
            path.fill()
            NSColor.windowBackgroundColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    static func color(for tag: String) -> NSColor {
        switch TagColor.index(of: tag) {
        case 0: .systemRed
        case 1: .systemOrange
        case 2: .systemYellow
        case 3: .systemGreen
        case 4: .systemBlue
        case 5: .systemPurple
        default: .systemGray
        }
    }
}

enum CloudBadge {
    /// Nothing for downloaded items (the usual case), a cloud for the rest.
    static func image(_ status: CloudStatus?) -> NSImage? {
        let symbol: String
        switch status {
        case nil, .current: return nil
        case .notDownloaded: symbol = "icloud.and.arrow.down"
        case .downloading: symbol = "arrow.down.circle.dotted"
        case .uploading: symbol = "icloud.and.arrow.up"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: status?.title)
    }
}
