import Foundation

/// Read-only view of the file system, so planning can be tested with a fake.
public protocol FileTree {
    func entry(at url: URL) -> FileTreeEntry?
    /// Items directly inside a folder.
    func children(of folder: URL) -> [URL]
    /// The same item, however each URL is spelled (see `URL.isSameItem`).
    func isSameItem(_ a: URL, _ b: URL) -> Bool
    /// The path with symlinks followed (see `URL.realPath`).
    func realPath(_ url: URL) -> URL
}

extension FileTree {
    public func isSameItem(_ a: URL, _ b: URL) -> Bool { a.standardizedFileURL.path == b.standardizedFileURL.path }
    public func realPath(_ url: URL) -> URL { url }
}

public struct FileTreeEntry: Hashable, Sendable {
    public var isFolder: Bool
    public var size: Int64
    public init(isFolder: Bool, size: Int64 = 0) {
        self.isFolder = isFolder
        self.size = size
    }
}

public enum TransferMode: Sendable { case copy, move }

/// An item that would land on an existing one (a file on a file, or a file and a folder).
/// Two folders with the same name never conflict: they merge.
public struct TransferConflict: Hashable, Sendable {
    public var source: URL
    public var destination: URL
    public var sourceIsFolder: Bool
    public var destinationIsFolder: Bool
}

public enum ConflictResolution: Sendable { case replace, skip, keepBoth }

public enum TransferError: Error, Equatable, LocalizedError {
    case intoItself(String)
    /// Replace would trash the folder the item being moved or copied is in.
    case replacesItsOwnFolder(String)

    public var errorDescription: String? {
        switch self {
        case .intoItself(let name): "“\(name)” can't be moved or copied into itself."
        case .replacesItsOwnFolder(let name): "“\(name)” can't be replaced by an item inside it."
        }
    }
}

public struct TransferPlan: Sendable {
    public var steps: [FileStep] = []
    /// Work per step, for progress: bytes for a copy, 1 for anything else.
    public var stepUnits: [Int64] = []
    public var units: Int64 { stepUnits.reduce(0, +) }
    /// Items the user will see as the result (top level only), to select afterwards.
    public var results: [URL] = []
}

/// Plans a paste, drop or duplicate: what to copy or move where, how folders merge, and where
/// conflicts are. Pure: reads only through `FileTree`.
public struct TransferPlanner {
    public var tree: FileTree

    public init(tree: FileTree) { self.tree = tree }

    /// The conflicts the user has to decide, in order.
    public func conflicts(_ sources: [URL], into folder: URL, mode: TransferMode) throws -> [TransferConflict] {
        try planAsking(sources, into: folder, mode: mode).conflicts
    }

    /// The conflicts, and the plan if there are none (it's final then: nothing to ask), so a
    /// paste without clashes walks its sources once.
    public func planAsking(_ sources: [URL], into folder: URL, mode: TransferMode) throws
        -> (plan: TransferPlan, conflicts: [TransferConflict])
    {
        var found: [TransferConflict] = []
        let plan = try plan(sources, into: folder, mode: mode) { conflict in
            found.append(conflict)
            return .skip
        }
        return (plan, found)
    }

    /// - `resolve` answers each conflict.
    /// - Copying an item into the folder it's already in duplicates it ("name - Copy").
    /// - Moving an item into the folder it's already in does nothing.
    public func plan(
        _ sources: [URL], into folder: URL, mode: TransferMode,
        resolve: @escaping (TransferConflict) -> ConflictResolution
    ) throws -> TransferPlan {
        var state = State(resolve: resolve, mode: mode)
        let folder = folder.standardizedFileURL
        for source in sources.map(\.standardizedFileURL) {
            guard let entry = tree.entry(at: source) else { continue }
            if tree.realPath(folder).isItemOrInside(source, isSameItem: tree.isSameItem) {
                throw TransferError.intoItself(source.lastPathComponent)
            }
            if tree.isSameItem(source.deletingLastPathComponent(), folder) {
                guard mode == .copy else { continue }
                let name = FileNaming.duplicate(
                    source.lastPathComponent, isFolder: entry.isFolder, existing: names(in: folder, &state))
                let target = folder.appendingPathComponent(name)
                state.add(.copy(source, to: target), units: units(source, entry), creating: target)
                state.plan.results.append(target)
                continue
            }
            if let target = try place(source, entry, at: folder.appendingPathComponent(source.lastPathComponent), &state) {
                state.plan.results.append(target)
            }
        }
        return state.plan
    }

    private struct State {
        var plan = TransferPlan()
        var created: Set<URL> = []
        /// Names already in each destination folder, listed once.
        var listed: [String: Set<String>] = [:]
        let resolve: (TransferConflict) -> ConflictResolution
        let mode: TransferMode

        mutating func add(_ step: FileStep, units: Int64, creating url: URL? = nil) {
            plan.steps.append(step)
            plan.stepUnits.append(units)
            if let url {
                created.insert(url)
                listed[url.deletingLastPathComponent().path]?.insert(url.lastPathComponent)
            }
        }
    }

    /// Returns where the item ends up, or nil if skipped.
    private func place(_ source: URL, _ entry: FileTreeEntry, at target: URL, _ state: inout State) throws -> URL? {
        if state.created.contains(target) {
            // Two pasted items with the same name (from different folders): keep both.
            return placeRenamed(source, entry, target, &state)
        }
        guard let existing = tree.entry(at: target) else {
            state.add(transfer(source, target, state.mode), units: units(source, entry), creating: target)
            return target
        }
        if entry.isFolder && existing.isFolder {
            // Merge, like Explorer and Linux (Finder would replace the folder).
            for child in tree.children(of: source) {
                guard let childEntry = tree.entry(at: child) else { continue }
                _ = try place(child, childEntry, at: target.appendingPathComponent(child.lastPathComponent), &state)
            }
            if state.mode == .move { state.add(.removeEmptyFolder(source), units: 1) }
            return target
        }
        let conflict = TransferConflict(
            source: source, destination: target, sourceIsFolder: entry.isFolder, destinationIsFolder: existing.isFolder)
        switch state.resolve(conflict) {
        case .skip:
            return nil
        case .replace:
            if tree.realPath(source.deletingLastPathComponent()).isItemOrInside(target, isSameItem: tree.isSameItem) {
                throw TransferError.replacesItsOwnFolder(target.lastPathComponent)
            }
            state.add(.trash(target), units: 1)
            state.add(transfer(source, target, state.mode), units: units(source, entry), creating: target)
            return target
        case .keepBoth:
            return placeRenamed(source, entry, target, &state)
        }
    }

    private func placeRenamed(_ source: URL, _ entry: FileTreeEntry, _ target: URL, _ state: inout State) -> URL {
        let folder = target.deletingLastPathComponent()
        let name = FileNaming.keepBoth(
            target.lastPathComponent, isFolder: entry.isFolder, existing: names(in: folder, &state))
        let renamed = folder.appendingPathComponent(name)
        state.add(transfer(source, renamed, state.mode), units: units(source, entry), creating: renamed)
        return renamed
    }

    private func transfer(_ source: URL, _ target: URL, _ mode: TransferMode) -> FileStep {
        mode == .copy ? .copy(source, to: target) : .move(source, to: target)
    }

    /// What's in `folder` plus what the plan puts there so far. The folder is listed once and
    /// then kept up to date as names are taken (it was listed again, and every planned item
    /// scanned, for each renamed item).
    private func names(in folder: URL, _ state: inout State) -> Set<String> {
        if let names = state.listed[folder.path] { return names }
        var names = Set(tree.children(of: folder).map(\.lastPathComponent))
        for url in state.created where url.deletingLastPathComponent().path == folder.path {
            names.insert(url.lastPathComponent)
        }
        state.listed[folder.path] = names
        return names
    }

    /// Bytes for a copy (whole folder), so progress follows the data.
    private func units(_ url: URL, _ entry: FileTreeEntry) -> Int64 {
        guard entry.isFolder else { return max(entry.size, 1) }
        return tree.children(of: url).reduce(1) { total, child in
            total + (tree.entry(at: child).map { units(child, $0) } ?? 0)
        }
    }
}

/// The real file system.
public struct DiskFileTree: FileTree, Sendable {
    public init() {}

    public func entry(at url: URL) -> FileTreeEntry? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .isSymbolicLinkKey])
        else { return nil }
        // Packages (.app) and symlinks are copied as one item, never merged into.
        let isFolder = values.isDirectory == true && values.isPackage != true && values.isSymbolicLink != true
        return FileTreeEntry(isFolder: isFolder, size: Int64(values.fileSize ?? 0))
    }

    public func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    public func isSameItem(_ a: URL, _ b: URL) -> Bool { a.isSameItem(as: b) }
    public func realPath(_ url: URL) -> URL { url.realPath }
}

/// Paste and drop ask about each conflict in turn (Replace / Keep Both / Skip / Stop); an answer
/// can be applied to the rest.
public enum ConflictQuestions {
    /// An answer, and whether it goes for every remaining conflict. Nil means Stop.
    public typealias Answer = (resolution: ConflictResolution, applyToRest: Bool)?

    /// Asks `ask` about each conflict (with how many come after it) until one is answered for
    /// the rest. Nil if the user stopped. Answers are per conflict, not per destination: two
    /// pasted items with the same name each get their own.
    public static func answers(
        for conflicts: [TransferConflict],
        isolation: isolated (any Actor)? = #isolation,
        ask: (TransferConflict, _ remaining: Int) async -> Answer
    ) async -> [TransferConflict: ConflictResolution]? {
        var answers: [TransferConflict: ConflictResolution] = [:]
        var forAll: ConflictResolution?
        for (index, conflict) in conflicts.enumerated() {
            if let forAll {
                answers[conflict] = forAll
                continue
            }
            guard let answer = await ask(conflict, conflicts.count - index - 1) else { return nil }
            answers[conflict] = answer.resolution
            if answer.applyToRest { forAll = answer.resolution }
        }
        return answers
    }
}
