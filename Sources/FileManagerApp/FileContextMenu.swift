import AppKit
import FileManagerCore

/// The right-click menu (and Shift+F10) for the details list and the icon view: the selection's
/// commands over an item, the folder's commands over empty space.
@MainActor final class FileContextMenu: NSObject, NSMenuDelegate {
    let model: BrowserModel
    let menu = NSMenu()
    /// The item under the pointer when the menu opened; nil over empty space.
    var clickedItem: () -> URL? = { nil }
    /// Selects only this item (nil: nothing), as right-clicking does in Finder and Explorer.
    var select: (URL?) -> Void = { _ in }
    /// Opened with Shift+F10: acts on the selection, wherever the pointer is.
    var fromKeyboard = false

    init(model: BrowserModel) {
        self.model = model
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let clicked = clickedItem(), !fromKeyboard {
            if !model.selection.contains(clicked) { select(clicked) }
            buildItemMenu(menu)
        } else if fromKeyboard, !model.selection.isEmpty {
            buildItemMenu(menu)
        } else {
            if !fromKeyboard { select(nil) }
            buildFolderMenu(menu)
        }
    }

    private func buildItemMenu(_ menu: NSMenu) {
        let urls = model.selectedURLs
        guard let first = urls.first else { return }
        let selected = model.items.filter { model.selection.contains($0.url) }
        add(.open, to: menu)
        if selected.contains(where: \.isFolder) { add(.openInNewTab, to: menu) }
        menu.addItem(openWithItem(for: urls, first: first))
        add(.quickLook, to: menu)
        menu.addItem(.separator())
        add(.cut, to: menu)
        add(.copy, to: menu)
        add(.duplicate, to: menu)
        add(.rename, to: menu)
        menu.addItem(.separator())
        add(.copyPath, to: menu)
        add(.getInfo, to: menu)
        if selected.count == 1, selected[0].isFolder {
            let item = NSMenuItem(title: Action.openTerminal.title, action: #selector(openTerminalInFolder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = first
            menu.addItem(item)
        }
        add(.showInFinder, to: menu)
        if selected.contains(where: \.isFolder) { add(.addToSidebar, to: menu) }
        menu.addItem(.separator())
        if model.isTrashFolder {
            add(.putBack, to: menu)
        } else {
            add(.moveToTrash, to: menu)
        }
        menu.addItem(.separator())
        menu.addItem(NSSharingServicePicker(items: urls).standardShareMenuItem)
    }

    private func buildFolderMenu(_ menu: NSMenu) {
        add(.newFolder, to: menu)
        add(.newTextFile, to: menu)
        add(.paste, to: menu)
        menu.addItem(.separator())
        add(.viewAsIcons, to: menu).state = model.view.mode == .icons ? .on : .off
        add(.viewAsDetails, to: menu).state = model.view.mode == .details ? .on : .off
        menu.addItem(choiceMenu("Sort By", FileSort.Column.allCases.map { ($0.title, $0.rawValue) },
            current: model.view.sortColumn.rawValue, action: #selector(sortBy(_:))))
        menu.addItem(choiceMenu("Group By", GroupBy.allCases.map { ($0.title, $0.rawValue) },
            current: model.view.groupBy.rawValue, action: #selector(groupBy(_:))))
        add(.toggleHiddenFiles, to: menu).state = model.showHiddenFiles ? .on : .off
        add(.refresh, to: menu)
        menu.addItem(.separator())
        add(.openTerminal, to: menu)
        add(.copyPath, to: menu)
        add(.getInfo, to: menu)
        add(.showInFinder, to: menu)
        add(.addToSidebar, to: menu)
    }

    private func choiceMenu(_ title: String, _ choices: [(String, String)], current: String, action: Selector)
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (choiceTitle, raw) in choices {
            let entry = NSMenuItem(title: choiceTitle, action: action, keyEquivalent: "")
            entry.target = self
            entry.representedObject = raw
            entry.state = raw == current ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    @discardableResult
    private func add(_ action: Action, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        item.isEnabled = model.canPerform(action)
        menu.addItem(item)
        return item
    }

    /// Open With: apps that can open the first item, the default first.
    private func openWithItem(for urls: [URL], first: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: first)
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        if let defaultApp {
            apps.removeAll { $0 == defaultApp }
            apps.insert(defaultApp, at: 0)
        }
        var seen = Set<String>()
        for app in apps {
            let name = FileManager.default.displayName(atPath: app.path)
            guard seen.insert(name).inserted else { continue }
            let entry = NSMenuItem(
                title: app == defaultApp ? "\(name) (default)" : name, action: #selector(openWith(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
            if app == defaultApp, apps.count > 1 { submenu.addItem(.separator()) }
        }
        submenu.addItem(.separator())
        let other = NSMenuItem(title: "Other…", action: #selector(openWithOther(_:)), keyEquivalent: "")
        other.target = self
        submenu.addItem(other)
        item.submenu = submenu
        return item
    }

    @objc func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = Action(rawValue: raw) else { return }
        model.perform(action)
    }

    @objc func sortBy(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let column = FileSort.Column(rawValue: raw) else { return }
        model.view.sortColumn = column
    }

    @objc func groupBy(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let group = GroupBy(rawValue: raw) else { return }
        model.view.groupBy = group
    }

    @objc func openTerminalInFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        TerminalLauncher.open(folder)
    }

    @objc func openWith(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(model.selectedURLs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func openWithOther(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Open"
        let urls = model.selectedURLs
        guard panel.runModal() == .OK, let app = panel.url else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
