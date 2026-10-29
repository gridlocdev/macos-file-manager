import AppKit
import FileManagerCore
import Observation

/// One running operation, shown in the File Operations window.
@MainActor @Observable
final class FileJob: Identifiable {
    let id = UUID()
    let title: String
    let totalUnits: Int64
    private(set) var doneUnits: Int64 = 0
    private(set) var currentName = ""
    fileprivate var task: Task<FileStepExecutor.Outcome, Never>?

    init(title: String, totalUnits: Int64) {
        self.title = title
        self.totalUnits = max(totalUnits, 1)
    }

    var fraction: Double { min(Double(doneUnits) / Double(totalUnits), 1) }

    func cancel() { task?.cancel() }

    fileprivate func advance(_ units: Int64, name: String) {
        doneUnits += units
        currentName = name
    }
}

/// Runs every change to files: as background jobs with progress and cancel, with one undo
/// history for the whole app (like Explorer), and a log of what it moved to the Trash so it
/// can Put Back.
@MainActor @Observable
final class FileOperations {
    static let shared = FileOperations()

    private(set) var jobs: [FileJob] = []
    /// Set when a job has run long enough to show the progress window.
    private(set) var showProgress = false

    private struct UndoEntry {
        var title: String
        var steps: [FileStep]
    }
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    let trashLog = TrashLog()

    // MARK: Running steps

    enum History { case record, undo, redo, none }

    /// Runs steps as a job. Errors are shown in an alert on `window`. Whatever ran is recorded
    /// for undo, even after an error or Cancel, so a partial copy can be undone.
    @discardableResult
    func run(
        _ title: String, steps: [FileStep], stepUnits: [Int64]? = nil,
        history: History = .record, window: NSWindow?
    ) async -> FileStepExecutor.Outcome {
        guard !steps.isEmpty else { return .init() }
        let units = stepUnits ?? Array(repeating: 1, count: steps.count)
        let job = FileJob(title: title, totalUnits: units.reduce(0, +))
        jobs.append(job)
        let reveal = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { showProgress = true }
        }

        let executor = FileStepExecutor()
        let task = Task.detached(priority: .userInitiated) {
            executor.run(steps) { index in
                let step = steps[index]
                Task { @MainActor in job.advance(units[index], name: step.subject.lastPathComponent) }
            } isCancelled: {
                Task.isCancelled
            }
        }
        job.task = task
        let outcome = await task.value

        reveal.cancel()
        jobs.removeAll { $0 === job }
        if jobs.isEmpty { showProgress = false }
        trashLog.update(with: outcome.executed)

        if let inverse = FileUndo.inverse(of: outcome.executed), !inverse.isEmpty {
            let entry = UndoEntry(title: title, steps: inverse)
            switch history {
            case .record:
                undoStack.append(entry)
                redoStack.removeAll()
            case .undo: redoStack.append(entry)
            case .redo: undoStack.append(entry)
            case .none: break
            }
            if undoStack.count > 100 { undoStack.removeFirst() }
        }
        if let error = outcome.error {
            showError(error, title: "\(title) stopped", window: window)
        }
        // Tags just set can read back stale for a moment, so windows are told what they are.
        var tags: [String: [String]] = [:]
        for case .tagged(let url, _, let to) in outcome.executed { tags[url.normalized.path] = to }
        if !tags.isEmpty { Windows.shared.allModels.forEach { $0.tagsChanged(tags) } }
        return outcome
    }

    func undo(window: NSWindow?) async -> [URL] {
        guard let entry = undoStack.popLast() else { return [] }
        let outcome = await run("Undo \(entry.title)", steps: entry.steps, history: .undo, window: window)
        return outcome.executed.compactMap(\.resultURL)
    }

    func redo(window: NSWindow?) async -> [URL] {
        guard let entry = redoStack.popLast() else { return [] }
        let outcome = await run(entry.title.replacingOccurrences(of: "Undo ", with: ""), steps: entry.steps,
            history: .redo, window: window)
        return outcome.executed.compactMap(\.resultURL)
    }

    // MARK: Copy and move

    /// Copies or moves items into a folder, asking about each conflict. Returns the new items.
    func transfer(_ sources: [URL], into folder: URL, mode: TransferMode, window: NSWindow?) async -> [URL] {
        guard !sources.isEmpty else { return [] }
        let conflicts: [TransferConflict]
        do {
            conflicts = try await Task.detached {
                try TransferPlanner(tree: DiskFileTree()).conflicts(sources, into: folder, mode: mode)
            }.value
        } catch {
            showError(error, title: mode == .copy ? "Can't copy" : "Can't move", window: window)
            return []
        }

        var answers: [URL: ConflictResolution] = [:]
        var forAll: ConflictResolution?
        for (index, conflict) in conflicts.enumerated() {
            if let forAll {
                answers[conflict.destination] = forAll
                continue
            }
            guard let (answer, applyToAll) = await ask(conflict, mode: mode, remaining: conflicts.count - index - 1, window: window)
            else { return [] }
            answers[conflict.destination] = answer
            if applyToAll { forAll = answer }
        }

        let resolved = answers
        guard let plan = try? await Task.detached(operation: {
            try TransferPlanner(tree: DiskFileTree()).plan(sources, into: folder, mode: mode) {
                resolved[$0.destination] ?? .skip
            }
        }).value else { return [] }

        let verb = mode == .copy ? "Copying" : "Moving"
        let what = sources.count == 1 ? "“\(sources[0].lastPathComponent)”" : "\(sources.count) items"
        let title = "\(verb) \(what) to “\(FileManager.default.displayName(atPath: folder.path))”"
        let outcome = await run(title, steps: plan.steps, stepUnits: plan.stepUnits, window: window)
        let made = Set(outcome.executed.compactMap(\.resultURL).map(\.path))
        // Merged folders already existed, so count them as results too.
        return plan.results.filter { made.contains($0.path) || FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Replace / Keep Both / Skip, with "do this for the rest". Nil means Stop.
    private func ask(
        _ conflict: TransferConflict, mode: TransferMode, remaining: Int, window: NSWindow?
    ) async -> (ConflictResolution, Bool)? {
        let name = conflict.destination.lastPathComponent
        let folder = FileManager.default.displayName(atPath: conflict.destination.deletingLastPathComponent().path)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText =
            conflict.destinationIsFolder
            ? "A folder named “\(name)” already exists in “\(folder)”."
            : "An item named “\(name)” already exists in “\(folder)”."
        let verb = mode == .copy ? "copying" : "moving"
        alert.informativeText =
            conflict.destinationIsFolder || conflict.sourceIsFolder
            ? "Replacing it moves the existing \(conflict.destinationIsFolder ? "folder" : "file") to the Trash. Keep Both gives the one you're \(verb) a new name."
            : "Replace it with the one you're \(verb)? The existing file goes to the Trash. Keep Both gives the one you're \(verb) a new name."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Stop")
        if remaining > 0 {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title =
                remaining == 1 ? "Do this for the next conflict" : "Do this for the next \(remaining) conflicts"
        }
        let response = await present(alert, window: window)
        let all = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn: return (.replace, all)
        case .alertSecondButtonReturn: return (.keepBoth, all)
        case .alertThirdButtonReturn: return (.skip, all)
        default: return nil
        }
    }

    // MARK: Put Back

    /// Moves items this app trashed back to where they were. Returns what was put back.
    func putBack(_ items: [URL], window: NSWindow?) async -> [URL] {
        var steps: [FileStep] = []
        var unknown: [String] = []
        for item in items {
            guard let original = trashLog.original(of: item) else {
                unknown.append(item.lastPathComponent)
                continue
            }
            var target = original
            if FileManager.default.fileExists(atPath: target.path) {
                let folder = original.deletingLastPathComponent()
                let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                target = folder.appendingPathComponent(FileNaming.keepBoth(original.lastPathComponent, existing: names))
            }
            steps.append(.move(item, to: target))
        }
        if !unknown.isEmpty {
            let alert = NSAlert()
            alert.messageText =
                unknown.count == 1
                ? "File Manager can't put back “\(unknown[0])”."
                : "File Manager can't put back \(unknown.count) of these items."
            alert.informativeText =
                "It can only put back items it moved to the Trash itself. Use Put Back in Finder for the others."
            _ = await present(alert, window: window)
        }
        let outcome = await run("Put Back", steps: steps, window: window)
        return outcome.executed.compactMap(\.resultURL)
    }

    // MARK: Alerts

    func present(_ alert: NSAlert, window: NSWindow?) async -> NSApplication.ModalResponse {
        if let window, window.isVisible {
            return await alert.beginSheetModal(for: window)
        }
        return alert.runModal()
    }

    func showError(_ error: Error, title: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        Task { _ = await present(alert, window: window) }
    }
}

/// Where each item this app moved to the Trash came from, so Put Back works. Stored in
/// Application Support, never in the user's folders.
@MainActor
final class TrashLog {
    private var originals: [String: String] = [:]
    private let file: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("File Manager", isDirectory: true)
        file = support.appendingPathComponent("trash-log.json")
        if let data = try? Data(contentsOf: file),
            let saved = try? JSONDecoder().decode([String: String].self, from: data)
        {
            // Forget items that have since been emptied from the Trash.
            originals = saved.filter { FileManager.default.fileExists(atPath: $0.key) }
        }
    }

    func original(of trashed: URL) -> URL? {
        originals[trashed.standardizedFileURL.path].map { URL(fileURLWithPath: $0) }
    }

    func update(with executed: [ExecutedStep]) {
        var changed = false
        for step in executed {
            switch step {
            case .trashed(let original, let trashURL):
                originals[trashURL.standardizedFileURL.path] = original.standardizedFileURL.path
                changed = true
            case .moved(let from, _) where originals[from.standardizedFileURL.path] != nil:
                originals[from.standardizedFileURL.path] = nil
                changed = true
            default:
                break
            }
        }
        guard changed else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(originals).write(to: file, options: .atomic)
    }
}
