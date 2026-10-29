/// The app-wide undo and redo stacks of file operations (one history for every window, like
/// Explorer). Each entry holds the steps that reverse what was done (see `FileUndo`).
public struct UndoHistory: Sendable {
    public struct Entry: Hashable, Sendable {
        public var title: String
        public var steps: [FileStep]
        public init(title: String, steps: [FileStep]) {
            self.title = title
            self.steps = steps
        }
    }

    /// What produced the steps an entry reverses.
    public enum Source: Sendable { case action, undo, redo }

    public private(set) var undoStack: [Entry] = []
    public private(set) var redoStack: [Entry] = []
    /// The oldest undo entries are dropped past this many.
    public let limit: Int

    public init(limit: Int = 100) { self.limit = limit }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Records the reverse of something just run: a new action clears redo, an undo can be
    /// redone, and a redo can be undone again.
    public mutating func record(_ entry: Entry, from source: Source) {
        switch source {
        case .action:
            undoStack.append(entry)
            redoStack.removeAll()
        case .undo: redoStack.append(entry)
        case .redo: undoStack.append(entry)
        }
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
    }

    public mutating func popUndo() -> Entry? { undoStack.popLast() }
    public mutating func popRedo() -> Entry? { redoStack.popLast() }
}
