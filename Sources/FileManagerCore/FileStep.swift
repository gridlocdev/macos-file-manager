import Foundation

/// One change to the file system. Every file operation (paste, rename, trash, undo, Put Back)
/// is a list of these, run by `FileStepExecutor`.
public enum FileStep: Hashable, Sendable {
    case copy(URL, to: URL)
    case move(URL, to: URL)
    case createFolder(URL)
    case createFile(URL)
    case trash(URL)
    /// Removes a folder only if it's empty (the source of a merged move). Not an error otherwise.
    case removeEmptyFolder(URL)
    /// Permanent. Can't be undone.
    case delete(URL)
}

extension FileStep {
    /// The item being worked on, for progress text.
    public var subject: URL {
        switch self {
        case .copy(let url, _), .move(let url, _), .createFolder(let url), .createFile(let url), .trash(let url),
            .removeEmptyFolder(let url), .delete(let url):
            url
        }
    }
}

/// What a step actually did, which is what undo works from (the Trash picks its own name).
public enum ExecutedStep: Hashable, Sendable {
    case copied(URL, to: URL)
    case moved(URL, to: URL)
    case createdFolder(URL)
    case createdFile(URL)
    case trashed(URL, trashURL: URL)
    case removedFolder(URL)
    case deleted(URL)

    /// The item this step created or put somewhere, if any.
    public var resultURL: URL? {
        switch self {
        case .copied(_, let to), .moved(_, let to): to
        case .createdFolder(let url), .createdFile(let url): url
        case .trashed, .removedFolder, .deleted: nil
        }
    }
}

public enum FileUndo {
    /// The steps that reverse `executed`, last step first. Copies and new items go to the Trash
    /// rather than being deleted. Nil if anything can't be reversed (a permanent delete).
    public static func inverse(of executed: [ExecutedStep]) -> [FileStep]? {
        var steps: [FileStep] = []
        for step in executed.reversed() {
            switch step {
            case .copied(_, let to): steps.append(.trash(to))
            case .moved(let from, let to): steps.append(.move(to, to: from))
            case .createdFolder(let url), .createdFile(let url): steps.append(.trash(url))
            case .trashed(let original, let trashURL): steps.append(.move(trashURL, to: original))
            case .removedFolder(let url): steps.append(.createFolder(url))
            case .deleted: return nil
            }
        }
        return steps
    }
}
