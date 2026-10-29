import AppKit
import FileManagerCore
import SwiftUI

/// Get Info (Cmd+I, Opt+Return): Explorer's Properties. One window per selection; folder sizes
/// are added up in the background and stop when the window closes.
struct InfoWindow: View {
    let urls: [URL]

    static let id = "info"

    var body: some View {
        Group {
            if urls.count == 1 {
                ItemInfo(url: urls[0])
            } else {
                SelectionInfo(urls: urls)
            }
        }
        .frame(width: 360)
        .fixedSize()
    }
}

private struct ItemInfo: View {
    let url: URL
    @State private var size: FolderSize?

    var body: some View {
        let info = Details(url)
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
                            .font(.headline)
                            .textSelection(.enabled)
                        Text(info.kind).foregroundStyle(.secondary)
                    }
                }
            }
            Section("General") {
                LabeledContent("Size", value: sizeText(info))
                LabeledContent("Where") {
                    Text(url.deletingLastPathComponent().path).textSelection(.enabled).lineLimit(3)
                }
                LabeledContent("Created", value: date(info.created))
                LabeledContent("Modified", value: date(info.modified))
                LabeledContent("Last opened", value: date(info.opened))
                if let app = info.opensWith { LabeledContent("Opens with", value: app) }
                if info.isHidden { LabeledContent("Hidden", value: "Yes") }
            }
            if let posix = info.posix {
                Section("Permissions") {
                    LabeledContent(info.owner ?? "Owner", value: Permissions.access(posix >> 6 & 7))
                    LabeledContent(info.group.map { "\($0) (group)" } ?? "Group", value: Permissions.access(posix >> 3 & 7))
                    LabeledContent("Everyone", value: Permissions.access(posix & 7))
                    LabeledContent("Mode") {
                        Text(Permissions.symbolic(posix, isFolder: info.isFolder) + String(format: "  (%o)", posix))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("\(url.lastPathComponent) Info")
        .task(id: url) {
            guard info.isFolder else { return }
            size = nil
            let url = url
            size = await Task.detached(priority: .utility) {
                FolderSize.measure(url) { Task.isCancelled }
            }.value
        }
    }

    private func sizeText(_ info: Details) -> String {
        if !info.isFolder {
            let bytes = info.size ?? 0
            return "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) (\(bytes.formatted()) bytes)"
        }
        guard let size else { return "Calculating…" }
        let items = size.files + size.folders
        return "\(ByteCountFormatter.string(fromByteCount: size.bytes, countStyle: .file)) for \(items.formatted()) \(items == 1 ? "item" : "items") "
            + "(\(ByteCountFormatter.string(fromByteCount: size.allocatedBytes, countStyle: .file)) on disk)"
    }

    private func date(_ date: Date?) -> String {
        date?.formatted(date: .long, time: .shortened) ?? "--"
    }
}

/// Several items: how many, and their total size.
private struct SelectionInfo: View {
    let urls: [URL]
    @State private var total: FolderSize?

    var body: some View {
        Form {
            Section {
                LabeledContent("Items", value: urls.count.formatted())
                LabeledContent("Total size") {
                    if let total {
                        Text("\(ByteCountFormatter.string(fromByteCount: total.bytes, countStyle: .file)) (\(total.bytes.formatted()) bytes)")
                    } else {
                        Text("Calculating…")
                    }
                }
                LabeledContent("Where") {
                    Text(Set(urls.map { $0.deletingLastPathComponent().path }).sorted().joined(separator: "\n"))
                        .textSelection(.enabled)
                }
            }
            Section("Items") {
                ForEach(urls, id: \.self) { url in
                    Label {
                        Text(url.lastPathComponent)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxHeight: 480)
        .navigationTitle("\(urls.count) Items Info")
        .task(id: urls) {
            let urls = urls
            total = await Task.detached(priority: .utility) {
                var sum = FolderSize()
                for url in urls {
                    if Task.isCancelled { break }
                    if Details(url).isFolder {
                        let size = FolderSize.measure(url) { Task.isCancelled }
                        sum.bytes += size.bytes
                        sum.allocatedBytes += size.allocatedBytes
                        sum.files += size.files
                        sum.folders += size.folders + 1
                    } else {
                        sum.bytes += Details(url).size ?? 0
                        sum.files += 1
                    }
                }
                return sum
            }.value
        }
    }
}

/// What Get Info shows about one item, read once.
private struct Details: Sendable {
    var kind = ""
    var isFolder = false
    var isHidden = false
    var size: Int64?
    var created: Date?
    var modified: Date?
    var opened: Date?
    var posix: Int?
    var owner: String?
    var group: String?
    var opensWith: String?

    init(_ url: URL) {
        let keys: Set<URLResourceKey> = [
            .localizedTypeDescriptionKey, .isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey,
            .creationDateKey, .contentModificationDateKey, .contentAccessDateKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        kind = values?.localizedTypeDescription ?? ""
        isFolder = values?.isDirectory == true && values?.isPackage != true
        isHidden = values?.isHidden ?? false
        size = values?.fileSize.map(Int64.init)
        created = values?.creationDate
        modified = values?.contentModificationDate
        opened = values?.contentAccessDate
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        posix = (attributes?[.posixPermissions] as? NSNumber)?.intValue
        owner = attributes?[.ownerAccountName] as? String
        group = attributes?[.groupOwnerAccountName] as? String
        if !isFolder, let app = NSWorkspace.shared.urlForApplication(toOpen: url) {
            opensWith = FileManager.default.displayName(atPath: app.path)
        }
    }
}
