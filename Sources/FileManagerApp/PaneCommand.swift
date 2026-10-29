import Foundation
import FileManagerCore
import SwiftUI

/// What a `BrowserModel` asks its views to do once. Sent with `BrowserModel.send`; views take
/// them with `onPaneCommand` (SwiftUI) or `BrowserModel.takeFileViewCommands()` (the file views).
enum PaneCommand: Sendable {
    /// For the file list or icon view.
    case focusList, rename(URL), quickLook, contextMenu
    case focusAddressBar
    case focusSearch
    /// For the window.
    case toggleSplit, connectToServer, getInfo([URL]), open(WindowSpec)
}

extension View {
    /// Runs `perform` for each command `model` sends from now on.
    func onPaneCommand(_ model: BrowserModel, perform: @escaping (PaneCommand) -> Void) -> some View {
        modifier(PaneCommandReceiver(model: model, perform: perform))
    }
}

private struct PaneCommandReceiver: ViewModifier {
    var model: BrowserModel
    var perform: (PaneCommand) -> Void
    @State private var seen: Int?

    func body(content: Content) -> some View {
        content
            .onAppear { if seen == nil { seen = model.commands.last } }
            .onChange(of: model.commands.last) {
                let new = model.commands.commands(after: seen ?? model.commands.last)
                seen = model.commands.last
                new.forEach(perform)
            }
    }
}
