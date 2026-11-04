import AppKit
import FileManagerCore
import Foundation
import Testing

@testable import FileManagerApp

/// Answers the model's questions the way a test says, and counts beeps.
@MainActor final class FakePresenter: BrowserPresenter {
    var beeps = 0
    var confirmAnswer = true
    var confirmations: [String] = []
    var pattern: (pattern: String, adding: Bool)?
    var problems: [String] = []

    func beep() { beeps += 1 }
    func confirm(_ title: String, detail: String, button: String, destructive: Bool) async -> Bool {
        confirmations.append(title)
        return confirmAnswer
    }
    func showProblem(_ title: String, detail: String) { problems.append(title) }
    func showError(_ error: Error, title: String) { problems.append(title) }
    func askForPattern(initial: String) async -> (pattern: String, adding: Bool)? { pattern }
}

/// A scratch folder with a few files, and services that keep everything (settings, the session,
/// folder views, the Trash, the clipboard) out of the user's own.
@MainActor final class Sandbox {
    let root: URL
    let services: BrowserServices
    let presenter = FakePresenter()
    private let suite: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FileManagerAppTests-\(UUID().uuidString)").canonical
        let fm = FileManager.default
        for folder in ["Projects", "Receipts", ".config", "Trash", "State"] {
            try fm.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        for name in ["notes.txt", "file2.txt", "file10.txt", ".hidden", "Projects/plan.txt"] {
            try Data("x".utf8).write(to: root.appending(path: name))
        }

        suite = "FileManagerAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // Saved pins, so the sidebar doesn't look for the default ones in Home.
        defaults.set(Data(#"{"paths":[]}"#.utf8), forKey: "sidebarPins")
        let trash = root.appending(path: "Trash")
        let executor = FileStepExecutor { url in
            let target = trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        let state = root.appending(path: "State")
        let presenter = presenter
        services = BrowserServices(
            operations: FileOperations(
                trashLog: TrashLog(file: state.appending(path: "trash-log.json")), executor: executor,
                reportError: { title, _ in presenter.problems.append(title) }),
            windows: Windows(defaults: defaults),
            sidebar: SidebarStore(defaults: defaults),
            folderViews: FolderViewStore(file: state.appending(path: "FolderViews.json")),
            clipboard: Clipboard(pasteboard: NSPasteboard(name: NSPasteboard.Name(suite))),
            preferences: Preferences(defaults: defaults))
    }

    func model(at folder: URL? = nil) -> BrowserModel {
        BrowserModel(start: folder ?? root, services: services, presenter: presenter)
    }

    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: root.appending(path: name).path) }

    func names(_ model: BrowserModel) -> [String] { model.items.map(\.name) }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

/// Waits for something the model does in the background (a folder read, a file operation).
@MainActor func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out")
}

@MainActor @Suite struct BrowserModelTests {
    let sandbox: Sandbox
    init() throws { sandbox = try Sandbox() }

    func started(at folder: URL? = nil) async throws -> BrowserModel {
        let model = sandbox.model(at: folder)
        model.start()
        try await eventually { !model.isLoading && model.listingVersion > 0 }
        return model
    }

    @Test func listsFoldersFirstAndHidesHiddenFiles() async throws {
        let model = try await started()
        #expect(sandbox.names(model) == ["Projects", "Receipts", "State", "Trash", "file2.txt", "file10.txt", "notes.txt"])
        model.perform(.toggleHiddenFiles)
        #expect(sandbox.names(model).contains(".hidden"))
    }

    @Test func goingUpSelectsTheFolderYouCameFrom() async throws {
        let model = try await started()
        model.navigate(to: sandbox.root.appending(path: "Projects/"))
        try await eventually { model.items.map(\.name) == ["plan.txt"] }
        model.perform(.goUp)
        try await eventually { model.selectedItems.map(\.name) == ["Projects"] }
        #expect(model.canPerform(.goForward) == false)
        #expect(model.canPerform(.goBack))
    }

    @Test func theFolderLeftIsntActedOnWhileTheNextLoads() async throws {
        let model = try await started()
        model.navigate(to: sandbox.root.appending(path: "Projects"))
        #expect(model.items.isEmpty)
        model.perform(.selectAll)
        #expect(model.selection.isEmpty)
        try await eventually { sandbox.names(model) == ["plan.txt"] }
    }

    @Test func duplicateAndCompressSearchResultsWhereTheyAre() async throws {
        try Data("y".utf8).write(to: sandbox.root.appending(path: "Receipts/plan.txt"))
        let model = try await started()
        model.perform(.find)
        model.searchScope = .subfolders
        model.criteria.text = "plan"
        try await eventually { model.items.count == 2 && !model.isSearching }
        model.perform(.selectAll)
        model.perform(.duplicate)
        try await eventually { sandbox.exists("Projects/plan - Copy.txt") && sandbox.exists("Receipts/plan - Copy.txt") }
        #expect(!sandbox.exists("plan - Copy.txt"))
        model.selection = [sandbox.root.appending(path: "Projects/plan.txt").normalized,
            sandbox.root.appending(path: "Receipts/plan.txt").normalized]
        model.perform(.compress)
        try await eventually { sandbox.exists("Archive.zip") }
        #expect(sandbox.presenter.problems.isEmpty)
    }

    @Test func backReturnsToTheSearchAsItWas() async throws {
        let model = try await started()
        model.perform(.find)
        model.searchScope = .subfolders
        model.criteria.text = "plan"
        try await eventually { model.items.map(\.name) == ["plan.txt"] && !model.isSearching }
        let plan = model.items[0].url
        model.selection = [plan]
        model.perform(.openContainingFolder)
        try await eventually { model.url.lastPathComponent == "Projects" && model.selection == [plan] }
        #expect(!model.search.isOpen)
        model.perform(.goBack)
        try await eventually { !model.isLoading && model.selection == [plan] }
        #expect(model.url.isSameFile(as: sandbox.root))
        #expect(model.search.isOpen && model.searchScope == .subfolders && model.criteria.text == "plan")
        #expect(model.items.map(\.name) == ["plan.txt"])
        // Forward and Back again: the search is kept each way.
        model.perform(.goForward)
        try await eventually { model.url.lastPathComponent == "Projects" && !model.search.isOpen }
        model.perform(.goBack)
        try await eventually { model.search.isOpen && model.items.map(\.name) == ["plan.txt"] }
    }

    @Test func renameCanDropAHiddenExtension() async throws {
        var notes = sandbox.root.appending(path: "notes.txt")
        var values = URLResourceValues()
        values.hasHiddenExtension = true
        try notes.setResourceValues(values)
        #expect(FileManager.default.displayName(atPath: notes.path) == "notes")
        let model = try await started()
        model.commitRename(notes.normalized, to: "notes")
        try await eventually { sandbox.exists("notes") }
        #expect(!sandbox.exists("notes.txt"))
    }

    @Test func whatAPasteDidntMoveStaysCut() {
        let clipboard = sandbox.services.clipboard
        let a = sandbox.root.appending(path: "notes.txt"), b = sandbox.root.appending(path: "file2.txt")
        clipboard.cut([a, b])
        clipboard.finishCut(leaving: [b])
        #expect(clipboard.isCut)
        #expect(clipboard.fileURLs.map(\.lastPathComponent) == ["file2.txt"])
        clipboard.finishCut()
        #expect(!clipboard.isCut && clipboard.fileURLs.isEmpty)
    }

    @Test func changesInTheFolderShowUpAgainAndAgain() async throws {
        let model = try await started()
        for name in ["new1.txt", "new2.txt"] {
            try Data().write(to: sandbox.root.appending(path: name))
            try await eventually { sandbox.names(model).contains(name) }
        }
    }

    @Test func findFiltersAndEndSearchRestores() async throws {
        let model = try await started()
        model.perform(.find)
        model.criteria.text = "file"
        #expect(sandbox.names(model) == ["file2.txt", "file10.txt"])
        #expect(model.folderItemCount == 7)
        model.perform(.endSearch)
        #expect(model.items.count == 7)
    }

    @Test func unavailableActionBeeps() async throws {
        let model = try await started()
        model.perform(.goBack)
        model.perform(.rename)
        #expect(sandbox.presenter.beeps == 2)
    }

    @Test func newFolderIsSelectedAndRenamedThenUndone() async throws {
        let model = try await started()
        model.perform(.newFolder)
        try await eventually { model.selectedItems.map(\.name) == [FileNaming.newFolderName] }
        #expect(sandbox.exists(FileNaming.newFolderName))
        #expect(model.takeFileViewCommands().contains {
            if case .rename(let url) = $0 { url.lastPathComponent == FileNaming.newFolderName } else { false }
        })
        model.perform(.undo)
        try await eventually { !sandbox.exists(FileNaming.newFolderName) }
    }

    @Test func deleteAsksFirst() async throws {
        let model = try await started()
        model.selection = [sandbox.root.appending(path: "notes.txt").normalized]
        sandbox.presenter.confirmAnswer = false
        model.perform(.deleteImmediately)
        try await eventually { sandbox.presenter.confirmations.count == 1 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(sandbox.exists("notes.txt"))
    }

    @Test func selectByPattern() async throws {
        let model = try await started()
        sandbox.presenter.pattern = ("file*", false)
        model.perform(.selectByPattern)
        try await eventually { model.selection.count == 2 }
        #expect(Set(model.selectedItems.map(\.name)) == ["file2.txt", "file10.txt"])
    }

    @Test func copyAndPaste() async throws {
        let model = try await started()
        model.selection = [sandbox.root.appending(path: "notes.txt").normalized]
        model.perform(.copy)
        model.navigate(to: sandbox.root.appending(path: "Receipts"))
        try await eventually { !model.isLoading && model.items.isEmpty }
        model.perform(.paste)
        try await eventually { sandbox.names(model) == ["notes.txt"] }
        #expect(model.selectedItems.map(\.name) == ["notes.txt"])
        #expect(sandbox.exists("notes.txt"))
    }
}

@MainActor @Suite struct KeyChordEventTests {
    func event(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    @Test func functionKeysUpToF20() {
        #expect(KeyChord(event(105, "")) == KeyChord(.function(13)))
        #expect(KeyChord(event(90, "")) == KeyChord(.function(20)))
    }

    @Test func commandChordsReadTheKeyAsTyped() {
        #expect(KeyChord(event(18, "1", .command)) == .char("1", .command))
        #expect(KeyChord(event(47, ">", [.command, .shift])) == .char(".", [.command, .shift]))
    }
}

@MainActor @Suite struct WindowsTests {
    let sandbox: Sandbox
    init() throws { sandbox = try Sandbox() }

    @Test func foldersOpenedBeforeTheFirstWindowSurviveTheSessionRestore() throws {
        let defaults = UserDefaults(suiteName: "WindowsTests-\(UUID().uuidString)")!
        let session = SessionState(windows: [.init(tabs: [sandbox.root.path, sandbox.root.appending(path: "Projects").path])])
        defaults.set(try JSONEncoder().encode(session), forKey: "session")
        let windows = Windows(defaults: defaults)
        // Open With arrives before SwiftUI asks for the first window.
        windows.openFromElsewhere([sandbox.root.appending(path: "Receipts")])
        #expect(windows.launchSpec().path == sandbox.root.path)
        let queued = windows.takeRestoreQueue().compactMap(\.path)
        #expect(queued == [sandbox.root.appending(path: "Projects").path, sandbox.root.appending(path: "Receipts").path])
    }
}

@MainActor @Suite struct FolderSearchTests {
    let sandbox: Sandbox
    init() throws { sandbox = try Sandbox() }

    @Test func walkListsItemsUnderTheFolderAsOpened() {
        // The sandbox is in /var/folders, really /private/var/folders.
        #expect(!sandbox.root.path.hasPrefix("/private/"))
        var found: [URL] = []
        FolderSearch.walk(sandbox.root, criteria: SearchCriteria(text: "plan"), showHidden: false, showAllExtensions: false) {
            found += $0.map(\.url)
        }
        #expect(found == [sandbox.root.appending(path: "Projects/plan.txt")])
    }
}

@MainActor @Suite struct ICloudDriveTests {
    let sandbox: Sandbox
    init() throws { sandbox = try Sandbox() }

    /// The sandbox as Home, with iCloud Drive keeping Desktop and Documents and three apps'
    /// containers: Numbers with documents, Pages empty (hidden) and Mail's private data.
    private func makeHome() throws -> URL {
        let home = sandbox.root, fm = FileManager.default
        let containers = home.appending(path: "Library/Mobile Documents")
        let drive = ICloudDrive.folder(home: home)
        for path in ["Desktop", "Documents", "Downloads"] {
            try fm.createDirectory(at: home.appending(path: path), withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: drive.appending(path: "Downloads"), withIntermediateDirectories: true)
        for name in ["com~apple~Numbers", "com~apple~Pages", "com~apple~mail"] {
            try fm.createDirectory(at: containers.appending(path: name + "/Documents"), withIntermediateDirectories: true)
        }
        for name in ["com~apple~Pages", "com~apple~mail"] {
            var url = containers.appending(path: name)
            var values = URLResourceValues()
            values.isHidden = true
            try url.setResourceValues(values)
        }
        for name in ["Desktop", "Documents"] {
            let link = drive.appending(path: name)
            try fm.createSymbolicLink(at: link, withDestinationURL: home.appending(path: name))
            #expect(lchflags(link.path, UInt32(UF_HIDDEN)) == 0)
        }
        return home
    }

    @Test func appFoldersAreTheVisibleContainersDocuments() throws {
        let home = try makeHome()
        let folders = ICloudDrive.appFolders(home: home).map(\.path)
        #expect(folders == [home.appending(path: "Library/Mobile Documents/com~apple~Numbers/Documents").path])
    }

    @Test func desktopAndDocumentsLinksCountAsSyncedHomeFolders() throws {
        let home = try makeHome()
        let drive = ICloudDrive.folder(home: home)
        #expect(ICloudDrive.isSyncedHomeFolder(drive.appending(path: "Desktop"), home: home))
        #expect(ICloudDrive.isSyncedHomeFolder(drive.appending(path: "Documents"), home: home))
        #expect(!ICloudDrive.isSyncedHomeFolder(drive.appending(path: "Downloads"), home: home))
        #expect(!ICloudDrive.isSyncedHomeFolder(home.appending(path: "Desktop"), home: home))
    }
}

@MainActor @Suite struct FileOperationsTests {
    let sandbox: Sandbox
    init() throws { sandbox = try Sandbox() }

    @Test func conflictAnswersComeFromAsk() async throws {
        let ops = sandbox.services.operations
        let source = sandbox.root.appending(path: "Projects/plan.txt")
        let target = sandbox.root.appending(path: "Receipts")
        try Data("old".utf8).write(to: target.appending(path: "plan.txt"))
        var asked: [String] = []
        let results = await ops.transfer([source], into: target, mode: .copy, window: nil) { conflict, _ in
            asked.append(conflict.destination.lastPathComponent)
            return (.keepBoth, false)
        }
        #expect(asked == ["plan.txt"])
        #expect(results.count == 1)
        #expect(results[0].lastPathComponent != "plan.txt")
        #expect(try String(contentsOf: target.appending(path: "plan.txt"), encoding: .utf8) == "old")
    }

    @Test func stopCopiesNothing() async throws {
        let ops = sandbox.services.operations
        let target = sandbox.root.appending(path: "Receipts")
        try Data("old".utf8).write(to: target.appending(path: "plan.txt"))
        let results = await ops.transfer(
            [sandbox.root.appending(path: "Projects/plan.txt")], into: target, mode: .copy, window: nil
        ) { _, _ in nil }
        #expect(results.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path) == ["plan.txt"])
        #expect(!ops.canUndo)
    }

    @Test func undoAndRedoAMove() async throws {
        let ops = sandbox.services.operations
        let from = sandbox.root.appending(path: "notes.txt")
        let to = sandbox.root.appending(path: "Receipts/notes.txt")
        await ops.run("Move", steps: [.move(from, to: to)], window: nil)
        #expect(sandbox.exists("Receipts/notes.txt"))
        _ = await ops.undo(window: nil)
        #expect(sandbox.exists("notes.txt") && !sandbox.exists("Receipts/notes.txt"))
        #expect(ops.canRedo)
        _ = await ops.redo(window: nil)
        #expect(sandbox.exists("Receipts/notes.txt"))
    }

    @Test func redoOfATrashTrashesAgain() async throws {
        let ops = sandbox.services.operations
        let notes = sandbox.root.appending(path: "notes.txt")
        let trash = sandbox.root.appending(path: "Trash")
        await ops.run("Move to Trash", steps: [.trash(notes)], window: nil)
        _ = await ops.undo(window: nil)
        #expect(sandbox.exists("notes.txt"))
        _ = await ops.redo(window: nil)
        let trashed = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
        #expect(trashed.count == 1)
        // Put Back still knows where it came from.
        #expect(trashed.first.flatMap { ops.trashLog.original(of: $0) }?.path == notes.path)
    }

    @Test func anUndoThatStopsKeepsTheRest() async throws {
        let ops = sandbox.services.operations
        let fm = FileManager.default
        let r = sandbox.root
        await ops.run(
            "Move", steps: [.move(r.appending(path: "notes.txt"), to: r.appending(path: "Receipts/notes.txt")),
                .move(r.appending(path: "file2.txt"), to: r.appending(path: "Receipts/file2.txt"))],
            window: nil)
        // Undo puts file2 back, then can't put notes back: something has taken its place.
        try Data("new".utf8).write(to: r.appending(path: "notes.txt"))
        _ = await ops.undo(window: nil)
        #expect(sandbox.exists("file2.txt") && sandbox.exists("Receipts/notes.txt"))
        #expect(ops.canUndo && ops.canRedo)
        // Once the way is clear, Undo finishes the job.
        try fm.removeItem(at: r.appending(path: "notes.txt"))
        _ = await ops.undo(window: nil)
        #expect(sandbox.exists("notes.txt") && !sandbox.exists("Receipts/notes.txt"))
        #expect(!ops.canUndo)
    }

    @Test func undoesRunOneAfterTheOther() async throws {
        let ops = sandbox.services.operations
        let r = sandbox.root
        await ops.run("Move", steps: [.move(r.appending(path: "notes.txt"), to: r.appending(path: "Receipts/notes.txt"))], window: nil)
        await ops.run(
            "Move", steps: [.move(r.appending(path: "Receipts/notes.txt"), to: r.appending(path: "Projects/notes.txt"))],
            window: nil)
        // The second undo needs the first one's result.
        async let first = ops.undo(window: nil)
        async let second = ops.undo(window: nil)
        _ = await (first, second)
        #expect(sandbox.exists("notes.txt"))
        #expect(!ops.canUndo)
    }
}
