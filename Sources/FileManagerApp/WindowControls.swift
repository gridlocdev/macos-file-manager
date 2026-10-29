import AppKit
import FileManagerCore

/// The AppKit side of a pane's window that `BrowserModel` needs: its tabs, and where the
/// keyboard focus is. Keeps `NSWindow` and the view tree out of the model's logic.
@MainActor final class WindowControls {
    weak var window: NSWindow?

    var tabCount: Int { window?.tabGroup?.windows.count ?? 1 }

    /// Brings the tab at `index` to the front, if there is one.
    func showTab(at index: Int) {
        let tabs = window?.tabGroup?.windows ?? []
        if tabs.indices.contains(index) { tabs[index].makeKeyAndOrderFront(nil) }
    }

    /// Next/previous tab, wrapping around.
    func showTab(offset: Int) {
        guard let window, let tabs = window.tabGroup?.windows, let index = tabs.firstIndex(of: window) else { return }
        tabs[(index + offset + tabs.count) % tabs.count].makeKeyAndOrderFront(nil)
    }

    enum Focus { case fileList, textField, other }

    var focus: Focus {
        switch window?.firstResponder {
        case is any FileBrowsingView: .fileList
        case is NSText: .textField
        default: .other
        }
    }

    /// Puts the focus in the sidebar. False if the window has none.
    func focusSidebar() -> Bool {
        guard let window, let sidebar = Self.sidebarView(in: window.contentView) else { return false }
        window.makeFirstResponder(sidebar)
        return true
    }

    /// The sidebar list's AppKit view: the first table or outline that isn't the file list.
    private static func sidebarView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is NSTableView, !(view is FileTableView) { return view }
        for child in view.subviews {
            if let found = sidebarView(in: child) { return found }
        }
        return nil
    }
}
