import AppKit
import FileManagerCore
import SwiftUI

extension View {
    /// Holding dragged files over this for a second calls `open`, so a drag can travel through
    /// folders without letting go; with `repeats`, again each second while still held. Files
    /// dropped go into `folder`, with the list's move/copy rules; with no folder, a drop here
    /// does nothing and the pointer says so.
    func springLoaded(
        into folder: URL?, model: BrowserModel, repeats: Bool = false, open: @escaping () -> Void
    ) -> some View {
        modifier(SpringLoaded(folder: folder, model: model, repeats: repeats, open: open))
    }
}

private struct SpringLoaded: ViewModifier {
    let folder: URL?
    let model: BrowserModel
    let repeats: Bool
    let open: () -> Void
    @State private var timer = SpringTimer()

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], delegate: Delegate(folder: folder, model: model, timer: timer) { [repeats, open] in
                timer.start(repeats: repeats, open)
            })
            .onDisappear { timer.stop() }
    }

    private struct Delegate: DropDelegate {
        let folder: URL?
        let model: BrowserModel
        let timer: SpringTimer
        let start: () -> Void

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
        func dropEntered(info: DropInfo) { start() }
        func dropExited(info: DropInfo) { timer.stop() }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            switch operation() {
            case .copy: DropProposal(operation: .copy)
            case .move: DropProposal(operation: .move)
            case .none: DropProposal(operation: .forbidden)
            }
        }

        func performDrop(info: DropInfo) -> Bool {
            timer.stop()
            let operation = operation()
            guard let folder, operation != .none else { return false }
            model.drop(FileDrop.draggedFiles(), into: folder, operation: operation)
            return true
        }

        private func operation() -> DropRules.Operation {
            guard let folder else { return .none }
            let files = FileDrop.draggedFiles()
            return files.isEmpty ? .none : FileDrop.operation(files, into: folder)
        }
    }
}

/// The wait before a held drag opens something.
@MainActor private final class SpringTimer {
    private var task: Task<Void, Never>?

    func start(repeats: Bool, _ open: @escaping () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            repeat {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                open()
            } while repeats
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
