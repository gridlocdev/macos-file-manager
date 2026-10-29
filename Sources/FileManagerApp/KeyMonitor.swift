import AppKit
import FileManagerCore
import SwiftUI

/// Runs keymap shortcuts for one window: every chord except the one each menu item shows,
/// which the menu runs. So plain keys (Backspace, F5) and second shortcuts (Opt+Left) work.
/// Skipped while a text field is being edited, so typing in the address bar works normally.
/// Also handles mouse back/forward buttons.
/// The model of the key window, for the menu bar. (`@FocusedValue` goes nil while an AppKit view
/// such as the file list has keyboard focus, which disabled every menu item.)
@MainActor @Observable
final class ActiveBrowser {
    static let shared = ActiveBrowser()
    var model: BrowserModel?
}

struct KeyMonitor: NSViewRepresentable {
    var model: BrowserModel
    var keymap: Keymap = .standard

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.model = model
        view.keymap = keymap
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.model = model
        view.keymap = keymap
    }

    final class MonitorView: NSView {
        var model: BrowserModel?
        var keymap = Keymap.standard
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            model?.window = window
            if let model { Windows.shared.attached(model, window: window) }
            // The menu bar acts on the key window's model.
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
            if window.isKeyWindow { windowDidBecomeKey() }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        @objc private func windowDidBecomeKey() {
            ActiveBrowser.shared.model = model
        }

        @objc private func windowWillClose() {
            if ActiveBrowser.shared.model === model { ActiveBrowser.shared.model = nil }
            if let model { Windows.shared.closed(model) }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, let model else { return event }
            if event.type == .otherMouseDown {
                switch event.buttonNumber {
                case 3: model.perform(.goBack)
                case 4: model.perform(.goForward)
                default: return event
                }
                return nil
            }
            if window.firstResponder is NSText { return event }
            guard let chord = KeyChord(event), let action = keymap.action(for: chord) else { return event }
            // The chord a menu item shows is left to the menu: SwiftUI runs menu shortcuts even
            // when a monitor swallows the event, so handling it here too would run it twice.
            if action.menu != nil, keymap.menuChord(for: action) == chord { return event }
            if action.isHandledByMacOS { return event }
            // Return renames and Delete trashes only in the file list, not the sidebar.
            if action.needsFileListFocus, !(window.firstResponder is FileTableView) { return event }
            model.perform(action)
            return nil
        }
    }
}

extension KeyChord {
    init?(_ event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        let key: Key
        switch event.keyCode {
        case 36, 76: key = .returnKey
        case 51: key = .delete
        case 117: key = .forwardDelete
        case 48: key = .tab
        case 49: key = .space
        case 53: key = .escape
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 122: key = .function(1)
        case 120: key = .function(2)
        case 99: key = .function(3)
        case 118: key = .function(4)
        case 96: key = .function(5)
        case 97: key = .function(6)
        case 98: key = .function(7)
        case 100: key = .function(8)
        case 101: key = .function(9)
        case 109: key = .function(10)
        case 103: key = .function(11)
        case 111: key = .function(12)
        default:
            // The key as typed without modifiers, so Cmd+Shift+. is "." not ">".
            guard let chars = event.characters(byApplyingModifiers: []), !chars.isEmpty else { return nil }
            key = .character(chars.lowercased())
        }
        self.init(key, modifiers)
    }

    /// The SwiftUI shortcut shown in menus.
    var keyboardShortcut: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        switch key {
        case .character(let c):
            guard let first = c.first else { return nil }
            equivalent = KeyEquivalent(first)
        case .returnKey: equivalent = .return
        case .delete: equivalent = .delete
        case .forwardDelete: equivalent = .deleteForward
        case .tab: equivalent = .tab
        case .space: equivalent = .space
        case .escape: equivalent = .escape
        case .up: equivalent = .upArrow
        case .down: equivalent = .downArrow
        case .left: equivalent = .leftArrow
        case .right: equivalent = .rightArrow
        case .function: return nil
        }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(equivalent, modifiers: eventModifiers)
    }
}
