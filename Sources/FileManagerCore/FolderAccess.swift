import Foundation

/// What to tell someone when macOS won't let the app open a folder, and which page of System
/// Settings fixes it.
public struct FolderAccessHelp: Equatable, Sendable {
    public enum Pane: String, Sendable {
        case filesAndFolders = "Privacy_FilesAndFolders"
        case fullDiskAccess = "Privacy_AllFiles"

        public var title: String {
            switch self {
            case .filesAndFolders: "Files & Folders"
            case .fullDiskAccess: "Full Disk Access"
            }
        }

        public var settingsURL: URL {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
        }
    }

    /// Where the folder is, as far as macOS's privacy settings go.
    public enum Volume: Sendable { case startup, removable, network }

    public var pane: Pane
    public var message: String

    /// For a folder macOS refused (EPERM: a privacy setting, not the folder's own permissions).
    public static func help(for folder: URL, home: URL, volume: Volume, isTrash: Bool) -> FolderAccessHelp {
        let guarded = ["Desktop", "Documents", "Downloads"].first {
            let protected = home.appending(path: $0)
            return folder.isSameFile(as: protected) || folder.isInside(protected)
        }
        let toggle: String? =
            if isTrash { nil }
            else if let guarded { "\(guarded) Folder" }
            else {
                switch volume {
                case .removable: "Removable Volumes"
                case .network: "Network Volumes"
                case .startup: nil
                }
            }
        guard let toggle else {
            let what = isTrash ? "the Trash" : "this folder"
            return FolderAccessHelp(
                pane: .fullDiskAccess,
                message: "macOS only lets apps with Full Disk Access open \(what). Turn on File Manager in "
                    + "System Settings → Privacy & Security → Full Disk Access, then press F5.")
        }
        return FolderAccessHelp(
            pane: .filesAndFolders,
            message: "macOS is blocking File Manager from this folder. In System Settings → Privacy & Security → "
                + "Files & Folders, open File Manager and turn on “\(toggle)”, then press F5.")
    }
}
