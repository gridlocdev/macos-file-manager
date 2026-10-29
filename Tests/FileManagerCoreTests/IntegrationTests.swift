import Foundation
import Testing

@testable import FileManagerCore

@Suite struct ArchiveTests {
    @Test func names() {
        #expect(Archive.archiveName(for: ["notes.txt"], existing: []) == "notes.txt.zip")
        #expect(Archive.archiveName(for: ["a", "b"], existing: ["Archive.zip"]) == "Archive (2).zip")
        #expect(Archive.folderName(for: "photos.zip") == "photos")
    }

    /// Runs the real ditto in a temporary folder of the test's own.
    @Test func compressAndExtractRoundTrip() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("fm-archive-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("b.txt")
        try Data("A".utf8).write(to: a)
        try Data("B".utf8).write(to: b)

        let executor = FileStepExecutor()
        let single = root.appendingPathComponent("a.txt.zip")
        let both = root.appendingPathComponent("Archive.zip")
        var outcome = executor.run([.compress([a], to: single), .compress([a, b], to: both)])
        #expect(outcome.error == nil)

        // One item inside: it comes out under its own name (made unique next to the original).
        outcome = executor.run([.extract(single, suggested: root.appendingPathComponent("a.txt"))])
        #expect(outcome.executed.first?.resultURL?.lastPathComponent == "a (2).txt")

        // Several: they go in a folder named after the archive.
        outcome = executor.run([.extract(both, suggested: root.appendingPathComponent("Archive"))])
        let folder = try #require(outcome.executed.first?.resultURL)
        #expect(folder.lastPathComponent == "Archive")
        #expect(Set(try fm.contentsOfDirectory(atPath: folder.path)) == ["a.txt", "b.txt"])

        // No staging folders left behind.
        #expect(try fm.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".") })
        #expect(FileUndo.inverse(of: outcome.executed) == [.trash(folder)])
    }

    @Test func tagChangesUndo() {
        let url = URL(filePath: "/x/a.txt")
        let steps = FileUndo.inverse(of: [.tagged(url, from: ["Red"], to: ["Red", "Work"])])
        #expect(steps == [.setTags(url, ["Red"])])
    }

    @Test func tagFilter() {
        var item = FileItem(url: URL(filePath: "/x/a"), name: "a", isFolder: false)
        item.tags = ["Work"]
        #expect(SearchCriteria(tag: "work").matches(item))
        #expect(!SearchCriteria(tag: "Red").matches(item))
        #expect(FileSort(column: .tags).sorted([FileItem(url: URL(filePath: "/x/b"), name: "b", isFolder: false), item])
            .first?.name == "a")
    }
}

@Suite struct CustomShortcutTests {
    @Test func parsesTheDocsSpelling() {
        for action in Action.allCases {
            for chord in Keymap.standard.chords(for: action) {
                #expect(KeyChord(parsing: chord.description) == chord, "\(chord)")
            }
        }
        #expect(KeyChord(parsing: "command+option+k") == .char("k", [.command, .option]))
        #expect(KeyChord(parsing: "Alt+Enter") == KeyChord(.returnKey, .option))
        #expect(KeyChord(parsing: "Cmd++") == .char("+", .command))
        #expect(KeyChord(parsing: "Hyper+K") == nil)
        #expect(KeyChord(parsing: "F99") == nil)
        #expect(KeyChord(parsing: "") == nil)
    }

    @Test func overridesReplaceAndSteal() {
        let (keymap, problems) = Keymap.standard.applying([
            "compress": ["Ctrl+Cmd+Z"],
            "rename": ["F2"],
            "refresh": ["Cmd+D"],
            "_comment": ["ignored"],
            "nonsense": ["F1"],
            "goUp": ["Cmd+Up", "Banana"],
        ])
        #expect(keymap.action(for: .char("z", [.command, .control])) == .compress)
        #expect(keymap.chords(for: .rename) == [KeyChord(.function(2))])
        #expect(keymap.action(for: KeyChord(.returnKey)) == nil)
        // Cmd+D belonged to Duplicate; now it refreshes.
        #expect(keymap.action(for: .char("d", .command)) == .refresh)
        #expect(keymap.chords(for: .duplicate).isEmpty)
        #expect(keymap.chords(for: .goUp) == [KeyChord(.up, .command)])
        #expect(problems.contains { $0.contains("nonsense") })
        #expect(problems.contains { $0.contains("Banana") })
        #expect(problems.contains { $0.contains("duplicate") })
        #expect(keymap.conflicts.isEmpty)
    }

    /// The Custom Shortcuts page lists every action's name for the shortcuts file.
    @Test func docsListEveryActionName() throws {
        let page = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/Custom-Shortcuts.md")
        let text = try String(contentsOf: page, encoding: .utf8)
        for action in Action.allCases {
            #expect(text.contains("`\(action.rawValue)`"), "\(action.rawValue) missing")
        }
    }
}

@Suite struct ServerAddressTests {
    func url(_ text: String) -> String? { try? ServerAddress.parse(text).get().absoluteString }

    @Test func addresses() {
        #expect(url("smb://nas.local/share") == "smb://nas.local/share")
        #expect(url("nas.local/share") == "smb://nas.local/share")
        #expect(url(#"\\nas\Shared Files"#) == "smb://nas/Shared%20Files")
        #expect(url("https://dav.example.com/files") == "https://dav.example.com/files")
        #expect(url("nfs://server/export") == "nfs://server/export")
        // Half Windows, half URL.
        #expect(url(#"smb:\\192.168.50.158\share"#) == "smb://192.168.50.158/share")
        #expect(url("smb:/nas/share") == "smb://nas/share")
        #expect(url("192.168.50.158/share") == "smb://192.168.50.158/share")
        #expect(url("nas:445/share") == "smb://nas:445/share")
    }

    @Test func problems() {
        #expect(ServerAddress.parse("  ") == .failure(.empty))
        #expect(ServerAddress.parse("sftp://host/home") == .failure(.unsupported(scheme: "sftp")))
        #expect(ServerAddress.parse("ftp://host") == .failure(.unsupported(scheme: "ftp")))
        #expect(ServerAddress.parse("smb://") == .failure(.invalid))
        #expect(ServerAddress.Problem.unsupported(scheme: "sftp").message.contains("SFTP"))
        #expect(ServerAddress.parse("http://dav.example.com/files") == .failure(.unsupported(scheme: "http")))
        #expect(ServerAddress.parse("HTTP://dav.example.com") == .failure(.unsupported(scheme: "http")))
        #expect(ServerAddress.Problem.unsupported(scheme: "http").message.contains("https://"))
    }

    @Test func recentServers() {
        let recent = ServerAddress.remember("smb://a", in: ["smb://b", "SMB://A", "smb://c"], limit: 3)
        #expect(recent == ["smb://a", "smb://b", "smb://c"])
    }

    @Test func recentServersLeaveOutPasswords() {
        #expect(ServerAddress.withoutPassword("smb://alice:secret@nas/share") == "smb://alice@nas/share")
        #expect(ServerAddress.withoutPassword("alice:secret@nas/share") == "alice@nas/share")
        #expect(ServerAddress.withoutPassword(#"\\alice:secret@nas\share"#) == #"\\alice@nas\share"#)
        #expect(ServerAddress.withoutPassword("smb://alice:p@ss@nas") == "smb://alice@nas")
        #expect(ServerAddress.withoutPassword(#"smb:\\alice:secret@nas\share"#) == #"smb:\\alice@nas\share"#)
        #expect(ServerAddress.withoutPassword("smb://alice@nas/share") == "smb://alice@nas/share")
        #expect(ServerAddress.withoutPassword("nas.local:445/share") == "nas.local:445/share")
        #expect(ServerAddress.withoutPassword("smb://nas/a:b@c") == "smb://nas/a:b@c")
        // Entries saved before this are cleaned too, and duplicates merge.
        let recent = ServerAddress.remember("smb://alice@nas", in: ["smb://alice:old@nas", "smb://bob:pw@x"])
        #expect(recent == ["smb://alice@nas", "smb://bob@x"])
    }
}
