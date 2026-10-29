import Foundation
import FileManagerCore

/// Each folder's view (icons or details, sort, groups, zoom), kept in Application Support
/// rather than in the folder itself (no .DS_Store-style files). Saved shortly after a change.
@MainActor
final class FolderViewStore {
    static let shared = FolderViewStore()

    private var memory: FolderViewMemory
    private var saveTask: Task<Void, Never>?
    private let file: URL

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("File Manager", isDirectory: true)
            .appendingPathComponent("FolderViews.json")
    }

    init(file: URL = defaultFile) {
        self.file = file
        memory = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(FolderViewMemory.self, from: $0) }
            ?? FolderViewMemory()
    }

    /// The folder's view, or the default one (details, by name).
    func view(for path: String) -> FolderView { memory.view(for: path) ?? FolderView() }

    func remember(_ view: FolderView, for path: String) {
        memory.remember(view, for: path)
        // Snapshot runs leave the user's saved views alone.
        guard !Windows.isSnapshotRun else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
