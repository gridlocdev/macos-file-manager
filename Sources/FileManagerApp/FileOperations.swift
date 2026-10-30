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

    private var history = UndoHistory()
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    let trashLog: TrashLog

    /// Runs the steps; tests give it one with a scratch Trash.
    private let executor: FileStepExecutor

    /// Shows an error (title, error); tests give one that records it instead of an alert.
    private let reportError: (@MainActor (String, Error) -> Void)?

    init(
        trashLog: TrashLog = TrashLog(), executor: FileStepExecutor = FileStepExecutor(),
        reportError: (@MainActor (String, Error) -> Void)? = nil
    ) {
        self.trashLog = trashLog
        self.executor = executor
        self.reportError = reportError
    }

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

        // Progress comes back through one stream, so it arrives in order.
        let (progress, reporter) = AsyncStream.makeStream(of: Int.self)
        let executor = executor
        let task = Task.detached(priority: .userInitiated) {
            defer { reporter.finish() }
            return executor.run(steps) { reporter.yield($0) } isCancelled: { Task.isCancelled }
        }
        job.task = task
        for await index in progress { job.advance(units[index], name: steps[index].subject.lastPathComponent) }
        let outcome = await task.value

        reveal.cancel()
        trashLog.update(with: outcome.executed)

        if let inverse = FileUndo.inverse(of: outcome.executed), !inverse.isEmpty {
            let entry = UndoHistory.Entry(title: title, steps: inverse)
            switch history {
            case .record: self.history.record(entry, from: .action)
            case .undo: self.history.record(entry, from: .undo)
            case .redo: self.history.record(entry, from: .redo)
            case .none: break
            }
        }
        // Only once its undo is recorded, so an undo waiting for it undoes the right thing.
        jobs.removeAll { $0 === job }
        if jobs.isEmpty {
            showProgress = false
            for waiter in idleWaiters { waiter.resume() }
            idleWaiters.removeAll()
        }
        if let error = outcome.error {
            showError(error, title: "\(title) stopped", window: window)
        }
        // Tags just set can read back stale for a moment, so windows are told what they are.
        var tags: [String: [String]] = [:]
        for case .tagged(let url, _, let to) in outcome.executed { tags[url.normalized.path] = to }
        if !tags.isEmpty { NotificationCenter.default.post(TagsChanged(tags: tags), subject: self) }
        return outcome
    }

    /// Undo and redo wait for running jobs, so two in a row don't run at once and one pressed
    /// during a copy undoes that copy, not the change before it.
    func undo(window: NSWindow?) async -> [URL] {
        await untilIdle()
        guard let entry = history.popUndo() else { return [] }
        let outcome = await run("Undo \(entry.title)", steps: entry.steps, history: .undo, window: window)
        putBackUnrun(entry, outcome, from: .undo)
        return outcome.executed.compactMap(\.resultURL)
    }

    func redo(window: NSWindow?) async -> [URL] {
        await untilIdle()
        guard let entry = history.popRedo() else { return [] }
        let outcome = await run(entry.title.replacingOccurrences(of: "Undo ", with: ""), steps: entry.steps,
            history: .redo, window: window)
        putBackUnrun(entry, outcome, from: .redo)
        return outcome.executed.compactMap(\.resultURL)
    }

    /// An undo or redo that stopped partway keeps the steps it didn't get to.
    private func putBackUnrun(_ entry: UndoHistory.Entry, _ outcome: FileStepExecutor.Outcome, from source: UndoHistory.Source) {
        guard outcome.stepsRun < entry.steps.count else { return }
        history.putBack(.init(title: entry.title, steps: Array(entry.steps[outcome.stepsRun...])), from: source)
    }

    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    private func untilIdle() async {
        while !jobs.isEmpty {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
    }

    // MARK: Copy and move

    /// Asks about one conflict, given how many come after it. Nil means Stop.
    typealias ConflictAsker = @MainActor (TransferConflict, _ remaining: Int) async -> ConflictQuestions.Answer

    /// Copies or moves items into a folder, asking about each conflict (with an alert on
    /// `window`, unless `ask` is given). Returns the new items.
    func transfer(
        _ sources: [URL], into folder: URL, mode: TransferMode, window: NSWindow?, ask: ConflictAsker? = nil
    ) async -> [URL] {
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

        let ask = ask ?? { [unowned self] conflict, remaining in
            await self.ask(conflict, mode: mode, remaining: remaining, window: window)
        }
        guard let resolved = await ConflictQuestions.answers(for: conflicts, ask: ask) else { return [] }
        let plan: TransferPlan
        do {
            plan = try await Task.detached {
                try TransferPlanner(tree: DiskFileTree()).plan(sources, into: folder, mode: mode) {
                    // A conflict that wasn't there when asking (the folder changed meanwhile) is skipped.
                    resolved[$0] ?? .skip
                }
            }.value
        } catch {
            showError(error, title: mode == .copy ? "Can't copy" : "Can't move", window: window)
            return []
        }

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
    ) async -> ConflictQuestions.Answer {
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
            steps.append(.restore(item, to: target))
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
        if let reportError { return reportError(title, error) }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        Task { _ = await present(alert, window: window) }
    }
}

/// Tags set by a file operation, keyed by path, so every window can show them at once (tags
/// just set can read back stale for a moment).
struct TagsChanged: NotificationCenter.MainActorMessage {
    typealias Subject = FileOperations
    var tags: [String: [String]]
}

/// Where each item this app moved to the Trash came from, so Put Back works. Stored in
/// Application Support, never in the user's folders.
@MainActor
final class TrashLog {
    private var originals: [String: String] = [:]
    private let file: URL

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("File Manager", isDirectory: true)
            .appendingPathComponent("trash-log.json")
    }

    init(file: URL = defaultFile) {
        self.file = file
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
            case .moved(let from, _) where originals[from.standardizedFileURL.path] != nil,
                .restored(let from, _) where originals[from.standardizedFileURL.path] != nil:
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
