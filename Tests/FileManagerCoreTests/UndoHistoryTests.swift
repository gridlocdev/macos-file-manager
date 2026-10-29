import Foundation
import Testing

@testable import FileManagerCore

@Suite struct UndoHistoryTests {
    func entry(_ title: String) -> UndoHistory.Entry {
        .init(title: title, steps: [.trash(URL(filePath: "/tmp/\(title)"))])
    }

    @Test func undoThenRedo() {
        var history = UndoHistory()
        history.record(entry("a"), from: .action)
        #expect(history.canUndo && !history.canRedo)
        #expect(history.popUndo() == entry("a"))
        history.record(entry("undo a"), from: .undo)
        #expect(history.canRedo)
        #expect(history.popRedo() == entry("undo a"))
        history.record(entry("redo a"), from: .redo)
        #expect(history.undoStack == [entry("redo a")])
    }

    @Test func newActionClearsRedo() {
        var history = UndoHistory()
        history.record(entry("a"), from: .action)
        _ = history.popUndo()
        history.record(entry("undo a"), from: .undo)
        history.record(entry("b"), from: .action)
        #expect(!history.canRedo)
    }

    @Test func dropsOldestPastLimit() {
        var history = UndoHistory(limit: 2)
        for title in ["a", "b", "c"] { history.record(entry(title), from: .action) }
        #expect(history.undoStack.map(\.title) == ["b", "c"])
    }
}

@Suite struct ConflictQuestionsTests {
    let conflicts = ["a", "b", "c"].map {
        TransferConflict(
            source: URL(filePath: "/src/\($0)"), destination: URL(filePath: "/dst/\($0)"), sourceIsFolder: false,
            destinationIsFolder: false)
    }

    @Test func asksEachInTurn() async {
        var remaining: [Int] = []
        let answers = await ConflictQuestions.answers(for: conflicts) { _, left in
            remaining.append(left)
            return (.keepBoth, false)
        }
        #expect(remaining == [2, 1, 0])
        #expect(answers?.values.allSatisfy { $0 == .keepBoth } == true)
        #expect(answers?.count == 3)
    }

    @Test func answerForTheRestStopsAsking() async {
        var asked = 0
        let answers = await ConflictQuestions.answers(for: conflicts) { conflict, _ in
            asked += 1
            return conflict.destination.lastPathComponent == "a" ? (.skip, false) : (.replace, true)
        }
        #expect(asked == 2)
        #expect(answers?[URL(filePath: "/dst/a")] == .skip)
        #expect(answers?[URL(filePath: "/dst/c")] == .replace)
    }

    @Test func stopReturnsNil() async {
        let answers = await ConflictQuestions.answers(for: conflicts) { _, _ in nil }
        #expect(answers == nil)
    }
}
