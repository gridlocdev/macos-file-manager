import Foundation

/// What you type in Connect to Server, turned into a URL macOS can mount.
public enum ServerAddress {
    public enum Problem: Error, Equatable, Sendable {
        case empty
        case unsupported(scheme: String)
        case invalid

        public var message: String {
            switch self {
            case .empty: "Type a server address, such as smb://nas.local/share."
            case .unsupported(let scheme) where scheme == "sftp" || scheme == "ssh":
                "macOS can't connect to SFTP servers by itself. Use an app such as Cyberduck or macFUSE with SSHFS, then open the mounted folder here."
            case .unsupported(let scheme) where scheme == "http":
                "WebDAV over http:// sends your password and files unencrypted. Use the server's https:// address instead."
            case .unsupported(let scheme): "File Manager can't connect to “\(scheme)” servers. Use smb, nfs or a WebDAV (https) address."
            case .invalid: "That doesn't look like a server address."
            }
        }
    }

    /// Schemes macOS mounts itself (WebDAV is https; plain http is refused as unencrypted).
    public static let schemes = ["smb", "nfs", "afp", "https"]

    /// "smb://nas/share" as is; "\\\\nas\\share" (Windows) and "nas/share" become smb.
    public static func parse(_ text: String) -> Result<URL, Problem> {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        // Windows habits: "\\nas\share", or half and half: "smb:\\nas\share", "smb:/nas/share".
        text = text.replacingOccurrences(of: "\\", with: "/")
        if text.hasPrefix("//") {
            text = "smb:" + text
        } else if let match = text.firstMatch(of: /^([A-Za-z][A-Za-z0-9+.-]*):\/+/) {
            text = "\(match.1)://" + text[match.range.upperBound...]
        } else {
            text = "smb://" + text
        }
        guard let scheme = text.components(separatedBy: "://").first?.lowercased(), !scheme.isEmpty else {
            return .failure(.invalid)
        }
        guard schemes.contains(scheme) else { return .failure(.unsupported(scheme: scheme)) }
        // Spaces in share names are common ("Shared Files"); encode what URL won't take. The
        // server part keeps the brackets of an IPv6 address ("[fe80::1]"); the path encodes them.
        let schemeEnd = text.range(of: "://")!.upperBound
        let pathStart = text[schemeEnd...].firstIndex(of: "/") ?? text.endIndex
        let allowed = CharacterSet.urlFragmentAllowed.union(["%"])
        let server = text[schemeEnd..<pathStart].addingPercentEncoding(withAllowedCharacters: allowed.union(["[", "]"]))
        let path = text[pathStart...].addingPercentEncoding(withAllowedCharacters: allowed)
        let encoded = server.flatMap { server in path.map { text[..<schemeEnd] + server + $0 } } ?? text
        guard let url = URL(string: encoded), let host = url.host(), !host.isEmpty else { return .failure(.invalid) }
        return .success(url)
    }

    /// Recently used servers, newest first, without repeats. Passwords are left out (they'd be
    /// stored in plain text); the keychain keeps them instead.
    public static func remember(_ address: String, in recent: [String], limit: Int = 10) -> [String] {
        let address = withoutPassword(address)
        let others = recent.map(withoutPassword).filter { $0.caseInsensitiveCompare(address) != .orderedSame }
        var seen = Set<String>()
        return Array(([address] + others).filter { seen.insert($0.lowercased()).inserted }.prefix(limit))
    }

    /// "smb://alice:secret@nas/share" → "smb://alice@nas/share", in any form `parse` takes.
    public static func withoutPassword(_ text: String) -> String {
        // The host part: after the scheme and slashes, up to the first slash. As in `parse`, a
        // scheme needs a slash after it ("alice:secret@nas" is a name and password).
        var start = text.startIndex
        if let match = text.firstMatch(of: /^(?:[A-Za-z][A-Za-z0-9+.-]*:(?=[\/\\]))?[\/\\]*/) {
            start = match.range.upperBound
        }
        let end = text[start...].firstIndex { $0 == "/" || $0 == "\\" } ?? text.endIndex
        guard let at = text[start..<end].lastIndex(of: "@"), let colon = text[start..<at].firstIndex(of: ":")
        else { return text }
        return String(text[..<colon] + text[at...])
    }
}
