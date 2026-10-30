import Foundation

/// Zip archives, made and opened with `ditto` (what Finder's Compress and Archive Utility use),
/// so Mac metadata such as tags and extended attributes is kept.
public enum Archive {
    /// "notes.txt.zip" for one item (as Finder names it), "Archive.zip" for several; made unique.
    public static func archiveName(for names: [String], existing: Set<String>) -> String {
        let name = names.count == 1 ? "\(names[0]).zip" : "Archive.zip"
        return FileNaming.unique(name, existing: existing)
    }

    /// The folder an archive opens into: "photos.zip" → "photos".
    public static func folderName(for archive: String) -> String {
        FileNaming.split(archive).base
    }

    public static func isArchive(_ url: URL) -> Bool { url.pathExtension.lowercased() == "zip" }

    public struct ToolError: LocalizedError {
        public var message: String
        public var errorDescription: String? { message }
    }

    static func compress(_ sources: [URL], to archive: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: archive.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: archive.path])
        }
        if sources.count == 1 {
            // A folder goes in under its own name (--keepParent); a file needs no wrapper.
            var isFolder: ObjCBool = false
            fm.fileExists(atPath: sources[0].path, isDirectory: &isFolder)
            let keepParent = isFolder.boolValue ? ["--keepParent"] : []
            try ditto(["-c", "-k", "--sequesterRsrc"] + keepParent + [sources[0].path, archive.path])
            return
        }
        // Several items go in at the top of the archive: gather clones (instant on APFS) in a
        // temporary folder next to the archive and zip its contents.
        let staging = archive.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        // Items from different folders (search results) can share a name: keep both.
        var names: Set<String> = []
        for source in sources {
            var isFolder: ObjCBool = false
            fm.fileExists(atPath: source.path, isDirectory: &isFolder)
            let name = FileNaming.keepBoth(source.lastPathComponent, isFolder: isFolder.boolValue, existing: names)
            names.insert(name)
            try fm.copyItem(at: source, to: staging.appendingPathComponent(name))
        }
        try ditto(["-c", "-k", "--sequesterRsrc", staging.path, archive.path])
    }

    /// Returns what was made: the single item inside, or the new folder.
    static func extract(_ archive: URL, suggested: URL) throws -> URL {
        let fm = FileManager.default
        let folder = archive.deletingLastPathComponent()
        let staging = folder.appendingPathComponent(".\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try ditto(["-x", "-k", archive.path, staging.path])

        let existing = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        let inside = try fm.contentsOfDirectory(atPath: staging.path).filter { $0 != "__MACOSX" }
        if inside.count == 1 {
            let item = staging.appendingPathComponent(inside[0])
            var isFolder: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isFolder)
            let target = folder.appendingPathComponent(
                FileNaming.unique(inside[0], isFolder: isFolder.boolValue, existing: existing))
            try fm.moveItem(at: item, to: target)
            return target
        }
        let target = folder.appendingPathComponent(
            FileNaming.unique(suggested.lastPathComponent, isFolder: true, existing: existing))
        try fm.moveItem(at: staging, to: target)
        return target
    }

    private static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ToolError(message: text.isEmpty ? "ditto failed (\(process.terminationStatus))." : text)
        }
    }
}
