import AppKit

/// What `BrowserModel` asks of the user: confirmations, problems, the Select by Pattern prompt
/// and the beep for an action that isn't available. A protocol, so the model never builds
/// alerts itself.
@MainActor protocol BrowserPresenter: AnyObject {
    func beep()
    /// A yes/no question; true if the user chose `button`.
    func confirm(_ title: String, detail: String, button: String, destructive: Bool) async -> Bool
    func showProblem(_ title: String, detail: String)
    func showError(_ error: Error, title: String)
    /// Select by Pattern: the pattern typed, and whether to add to the selection. Nil if cancelled.
    func askForPattern(initial: String) async -> (pattern: String, adding: Bool)?
}

/// Shows alerts as sheets on the pane's window (or as dialogs before it has one).
@MainActor final class AlertPresenter: BrowserPresenter {
    private let controls: WindowControls
    private let operations: FileOperations
    private var window: NSWindow? { controls.window }

    init(controls: WindowControls, operations: FileOperations) {
        self.controls = controls
        self.operations = operations
    }

    func beep() { NSSound.beep() }

    func confirm(_ title: String, detail: String, button: String, destructive: Bool) async -> Bool {
        let alert = NSAlert()
        if destructive { alert.alertStyle = .critical }
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return await operations.present(alert, window: window) == .alertFirstButtonReturn
    }

    func showProblem(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        Task { _ = await operations.present(alert, window: window) }
    }

    func showError(_ error: Error, title: String) {
        operations.showError(error, title: title, window: window)
    }

    func askForPattern(initial: String) async -> (pattern: String, adding: Bool)? {
        let alert = NSAlert()
        alert.messageText = "Select by Pattern"
        alert.informativeText = "Select items whose names match. Use * for any text and ? for one character; separate several patterns with “;”."
        let field = NSTextField(string: initial)
        field.placeholderString = "*.jpg; *.png"
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Select")
        alert.addButton(withTitle: "Add to Selection")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let response = await operations.present(alert, window: window)
        guard response != .alertThirdButtonReturn else { return nil }
        return (field.stringValue, response == .alertSecondButtonReturn)
    }
}
