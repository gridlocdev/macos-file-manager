import Foundation
import FileManagerCore

/// Finds items anywhere under a folder. Two searches run together and their results are merged:
/// Spotlight, which answers at once for indexed places, and a walk through the folder, which
/// finds what Spotlight leaves out (hidden files, ~/Library, unindexed disks, brand-new files).
/// Results arrive in batches; stops at `limit` items.
@MainActor
final class FolderSearch {
    static let limit = 5000

    private(set) var isFinished = false
    private(set) var hitLimit = false
    private let root: URL
    private let criteria: SearchCriteria
    private let showHidden: Bool
    private let showAllExtensions: Bool
    private let onResults: ([FileItem]) -> Void
    private let onFinish: () -> Void
    private var seen: Set<String> = []
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var tasks: [Task<Void, Never>] = []
    private var running = 0

    init(
        root: URL, criteria: SearchCriteria, showHidden: Bool, showAllExtensions: Bool,
        onResults: @escaping ([FileItem]) -> Void, onFinish: @escaping () -> Void
    ) {
        self.root = root
        self.criteria = criteria
        self.showHidden = showHidden
        self.showAllExtensions = showAllExtensions
        self.onResults = onResults
        self.onFinish = onFinish
    }

    func start() {
        startSpotlight()
        startWalk()
    }

    func cancel() {
        for task in tasks { task.cancel() }
        stopSpotlight()
        isFinished = true
    }

    // MARK: Results

    private func deliver(_ items: [FileItem]) {
        guard !isFinished else { return }
        var fresh: [FileItem] = []
        for item in items where seen.insert(item.url.path).inserted {
            fresh.append(item)
            if seen.count >= Self.limit {
                hitLimit = true
                break
            }
        }
        if !fresh.isEmpty { onResults(fresh) }
        if hitLimit {
            cancel()
            onFinish()
        }
    }

    private func finishedOne() {
        running -= 1
        guard running == 0, !isFinished else { return }
        isFinished = true
        onFinish()
    }

    // MARK: Walk

    private func startWalk() {
        running += 1
        let root = root, criteria = criteria, showHidden = showHidden, showAllExtensions = showAllExtensions
        tasks.append(Task {
            let batches = AsyncStream<[FileItem]> { continuation in
                let walker = Task.detached(priority: .userInitiated) {
                    Self.walk(root, criteria: criteria, showHidden: showHidden, showAllExtensions: showAllExtensions) {
                        continuation.yield($0)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in walker.cancel() }
            }
            for await batch in batches { deliver(batch) }
            finishedOne()
        })
    }

    private nonisolated static func walk(
        _ root: URL, criteria: SearchCriteria, showHidden: Bool, showAllExtensions: Bool, send: ([FileItem]) -> Void
    ) {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: DirectoryLoader.keys, options: options, errorHandler: { _, _ in true })
        else { return }
        var batch: [FileItem] = []
        var lastSend = Date()
        let now = Date()
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { return }
            let item = DirectoryLoader.item(url, showAllExtensions: showAllExtensions)
            if criteria.matches(item, now: now) { batch.append(item) }
            if !batch.isEmpty, batch.count >= 200 || Date().timeIntervalSince(lastSend) > 0.25 {
                send(batch)
                batch = []
                lastSend = Date()
            }
        }
        if !batch.isEmpty { send(batch) }
    }

    // MARK: Spotlight

    /// Needs a name to look for; filters alone are left to the walk.
    private func startSpotlight() {
        guard let predicate = NamePattern(criteria.text).spotlightPredicate else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [root]
        query.predicate = predicate
        running += 1
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.spotlightGathered() }
        }
        self.query = query
        if !query.start() {
            stopSpotlight()
            finishedOne()
        }
    }

    private func spotlightGathered() {
        guard let query else { return }
        query.disableUpdates()
        var paths: [String] = []
        for index in 0..<min(query.resultCount, Self.limit) {
            if let item = query.result(at: index) as? NSMetadataItem,
                let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            {
                paths.append(path)
            }
        }
        stopSpotlight()
        let root = root, criteria = criteria, showHidden = showHidden, showAllExtensions = showAllExtensions
        let found = paths
        tasks.append(Task {
            let items = await Task.detached(priority: .userInitiated) {
                Self.spotlightItems(
                    found, root: root, criteria: criteria, showHidden: showHidden, showAllExtensions: showAllExtensions)
            }.value
            if !Task.isCancelled { deliver(items) }
            finishedOne()
        })
    }

    /// Spotlight also reports items inside packages (an app's contents) and, with hidden files
    /// off, should match what the walk would find, so those are dropped.
    private nonisolated static func spotlightItems(
        _ paths: [String], root: URL, criteria: SearchCriteria, showHidden: Bool, showAllExtensions: Bool
    ) -> [FileItem] {
        let rootPath = root.path == "/" ? "" : root.path
        var isPackage: [String: Bool] = [:]
        let now = Date()
        return paths.compactMap { path in
            guard path.hasPrefix(rootPath + "/") else { return nil }
            let relative = path.dropFirst(rootPath.count + 1).split(separator: "/")
            if !showHidden, relative.contains(where: { $0.hasPrefix(".") }) { return nil }
            var folder = rootPath
            for component in relative.dropLast() {
                folder += "/" + component
                let package = isPackage[folder] ?? {
                    let values = try? URL(filePath: folder).resourceValues(forKeys: [.isPackageKey])
                    return values?.isPackage ?? false
                }()
                isPackage[folder] = package
                if package { return nil }
            }
            let item = DirectoryLoader.item(URL(filePath: path), showAllExtensions: showAllExtensions)
            if !showHidden, item.isHidden { return nil }
            return criteria.matches(item, now: now) ? item : nil
        }
    }

    private func stopSpotlight() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
