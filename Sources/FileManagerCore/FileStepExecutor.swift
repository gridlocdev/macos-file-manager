import Foundation

/// Runs `FileStep`s in order and reports what each actually did. Stops at the first error or
/// when cancelled, so the caller can still undo the part that ran. A folder being copied stops
/// between the items inside it; a single large file still copies to the end.
public struct FileStepExecutor: Sendable {
    /// Moves an item to the Trash and returns where it went. Injected so tests don't touch the
    /// real Trash.
    public var trash: @Sendable (URL) throws -> URL

    public init(trash: @escaping @Sendable (URL) throws -> URL = FileStepExecutor.systemTrash) {
        self.trash = trash
    }

    public static let systemTrash: @Sendable (URL) throws -> URL = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    public struct Outcome: Sendable {
        public var executed: [ExecutedStep] = []
        public var error: Error?
        public var cancelled = false
        public init() {}
    }

    /// - progress: called after each step with its index.
    /// - isCancelled: checked before each step.
    public func run(
        _ steps: [FileStep], progress: (Int) -> Void = { _ in },
        isCancelled: () -> Bool = { false }
    ) -> Outcome {
        // The copy delegate holds the check only while this runs.
        withoutActuallyEscaping(isCancelled) { isCancelled in
            run(steps, progress: progress, escapingIsCancelled: isCancelled)
        }
    }

    private func run(
        _ steps: [FileStep], progress: (Int) -> Void, escapingIsCancelled isCancelled: @escaping () -> Bool
    ) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        // Its own FileManager, whose delegate skips the rest of a folder once cancelled.
        let copier = FileManager()
        let copyDelegate = CopyDelegate(isCancelled: isCancelled)
        copier.delegate = copyDelegate
        defer { copier.delegate = nil }
        for (index, step) in steps.enumerated() {
            if isCancelled() {
                outcome.cancelled = true
                break
            }
            do {
                switch step {
                case .copy(let from, let to):
                    try copier.copyItem(at: from, to: to)
                    // Recorded even if cancelled partway, so undo removes the partial copy.
                    outcome.executed.append(.copied(from, to: to))
                    if isCancelled() {
                        outcome.cancelled = true
                        return outcome
                    }
                case .move(let from, let to):
                    try move(from, to)
                    outcome.executed.append(.moved(from, to: to))
                case .createFolder(let url):
                    try fm.createDirectory(at: url, withIntermediateDirectories: false)
                    outcome.executed.append(.createdFolder(url))
                case .createFile(let url):
                    guard !fm.fileExists(atPath: url.path) else {
                        throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
                    }
                    try Data().write(to: url, options: .withoutOverwriting)
                    outcome.executed.append(.createdFile(url))
                case .trash(let url):
                    let trashURL = try trash(url)
                    outcome.executed.append(.trashed(url, trashURL: trashURL))
                case .removeEmptyFolder(let url):
                    if (try? fm.contentsOfDirectory(atPath: url.path))?.isEmpty == true {
                        try fm.removeItem(at: url)
                        outcome.executed.append(.removedFolder(url))
                    }
                case .delete(let url):
                    try fm.removeItem(at: url)
                    outcome.executed.append(.deleted(url))
                case .compress(let sources, let archive):
                    try Archive.compress(sources, to: archive)
                    outcome.executed.append(.compressed(to: archive))
                case .extract(let archive, let suggested):
                    let result = try Archive.extract(archive, suggested: suggested)
                    outcome.executed.append(.extracted(archive, to: result))
                case .setTags(let url, let tags):
                    let old = (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
                    try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
                    outcome.executed.append(.tagged(url, from: old, to: tags))
                }
                progress(index)
            } catch {
                outcome.error = error
                break
            }
        }
        return outcome
    }

    /// Like `moveItem`, but a change of case only ("notes" → "Notes") works on a
    /// case-insensitive disk, by going through a temporary name.
    private func move(_ from: URL, _ to: URL) throws {
        let fm = FileManager.default
        if from.path != to.path, from.path.lowercased() == to.path.lowercased() {
            let temp = from.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
            try fm.moveItem(at: from, to: temp)
            try fm.moveItem(at: temp, to: to)
            return
        }
        let parent = to.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            // Putting something back where a folder no longer exists: recreate it, like Finder.
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try fm.moveItem(at: from, to: to)
    }
}

/// Says no to the rest of a folder copy once the job is cancelled.
private final class CopyDelegate: NSObject, FileManagerDelegate {
    let isCancelled: () -> Bool
    init(isCancelled: @escaping () -> Bool) { self.isCancelled = isCancelled }

    func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
        !isCancelled()
    }
}
