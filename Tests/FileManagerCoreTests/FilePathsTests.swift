import Foundation
import Testing

@testable import FileManagerCore

@Suite struct FilePathsTests {
    @Test func trailingSlashIsTheSameFolder() {
        let a = URL(filePath: "/Users/me/src/")
        let b = URL(filePath: "/Users/me/src", directoryHint: .notDirectory)
        #expect(a != b)
        #expect(a.isSameFile(as: b))
        #expect(a.normalized == b.normalized)
    }

    @Test func canonicalResolvesDots() {
        #expect(URL(filePath: "/a/b/../c/").canonical == URL(filePath: "/a/c", directoryHint: .notDirectory))
        #expect(URL(filePath: "/a/./b").canonical.path == "/a/b")
    }

    @Test func inside() {
        let src = URL(filePath: "/Users/me/src")
        #expect(URL(filePath: "/Users/me/src/app/x.swift").isInside(src))
        #expect(!URL(filePath: "/Users/me/src").isInside(src))
        #expect(!URL(filePath: "/Users/me/srcs/x").isInside(src))
        #expect(URL(filePath: "/Users").isInside(URL(filePath: "/")))
        #expect(URL(filePath: "/Users/me/src/x").isDirectlyInside(URL(filePath: "/Users/me/src/")))
        #expect(!URL(filePath: "/Users/me/src/a/x").isDirectlyInside(src))
    }

    @Test func replacingFolder() {
        let real = URL(filePath: "/private/tmp")
        let shown = URL(filePath: "/tmp")
        #expect(URL(filePath: "/private/tmp/a/b.txt").replacingFolder(real, with: shown).path == "/tmp/a/b.txt")
        #expect(URL(filePath: "/private/tmp").replacingFolder(real, with: shown).path == "/tmp")
        #expect(URL(filePath: "/Users/me/x").replacingFolder(real, with: shown).path == "/Users/me/x")
        #expect(URL(filePath: "/private/tmpfile").replacingFolder(real, with: shown).path == "/private/tmpfile")
    }

    @Test func realPath() {
        #expect(URL(filePath: "/tmp").realPath.path == "/private/tmp")
        #expect(URL(filePath: "/tmp/").realPath.path == "/private/tmp")
        #expect(URL(filePath: "/Users").realPath.path == "/Users")
        #expect(URL(filePath: "/no/such/place").realPath.path == "/no/such/place")
    }

    @Test func root() {
        #expect(URL(filePath: "/").isFileSystemRoot)
        #expect(!URL(filePath: "/Users").isFileSystemRoot)
    }

    @Test func trash() {
        let home = URL(filePath: "/Users/me")
        #expect(URL(filePath: "/Users/me/.Trash/").isTrashFolder(home: home))
        #expect(URL(filePath: "/Volumes/Disk/.Trashes/501").isTrashFolder(home: home))
        #expect(!URL(filePath: "/Users/me/Trash").isTrashFolder(home: home))
    }

    @Test func guardedFolders() {
        let home = URL(filePath: "/Users/me")
        #expect(URL(filePath: "/Users/me/Downloads").isGuardedFolder(home: home))
        #expect(URL(filePath: "/Users/me/Desktop/").isGuardedFolder(home: home))
        #expect(!URL(filePath: "/Users/me/Downloads/x").isGuardedFolder(home: home))
        #expect(!URL(filePath: "/Users/me/src").isGuardedFolder(home: home))
    }
}

@Suite struct FolderAccessTests {
    let home = URL(filePath: "/Users/me")

    @Test func guardedFoldersPointToTheirToggle() {
        let help = FolderAccessHelp.help(
            for: URL(filePath: "/Users/me/Downloads/old"), home: home, volume: .startup, isTrash: false)
        #expect(help.pane == .filesAndFolders)
        #expect(help.message.contains("“Downloads Folder”"))
    }

    @Test func drives() {
        let help = FolderAccessHelp.help(for: URL(filePath: "/Volumes/share"), home: home, volume: .network, isTrash: false)
        #expect(help.message.contains("“Network Volumes”"))
    }

    @Test func everythingElseNeedsFullDiskAccess() {
        let trash = FolderAccessHelp.help(for: URL(filePath: "/Users/me/.Trash"), home: home, volume: .startup, isTrash: true)
        #expect(trash.pane == .fullDiskAccess)
        #expect(trash.message.contains("the Trash"))
        let library = FolderAccessHelp.help(
            for: URL(filePath: "/Users/me/Library/Mail"), home: home, volume: .startup, isTrash: false)
        #expect(library.pane == .fullDiskAccess)
        #expect(library.pane.settingsURL.absoluteString.hasSuffix("?Privacy_AllFiles"))
    }
}
