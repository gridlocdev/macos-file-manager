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

/// Folder and app icons are per item; plain files share one icon per extension.
@MainActor final class IconCache {
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

/// What a drop does, for the list, the icon view and the sidebar.
enum FileDrop {
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
        }
    }
}

/// Settings that change how files are opened and shown.
enum ViewPreferences {
    static var singleClickOpens: Bool { UserDefaults.standard.bool(forKey: SettingsKey.singleClickOpen) }
}
