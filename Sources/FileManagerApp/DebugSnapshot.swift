#if DEBUG
import AppKit

/// `FILEMANAGER_SNAPSHOT=out.png` (debug builds): after launch, draws the front window (toolbar
/// included) into a PNG, prints the menu bar with its shortcuts, and quits. Steps in
/// FILEMANAGER_SNAPSHOT_KEYS: key chords ("Cmd+C"), "menu:Title" and "type:text". For checking the UI
/// and for docs screenshots without screen-recording permission. See `just snapshot`.
@MainActor enum DebugSnapshot {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["FILEMANAGER_SNAPSHOT"] else { return }
        let start = ProcessInfo.processInfo.environment["FILEMANAGER_SNAPSHOT_FOLDER"]
        Task {
            try? await Task.sleep(for: .seconds(1))
            // FILEMANAGER_SNAPSHOT_FOLDER: open this folder first (BrowserWindow listens).
            if let start {
                NotificationCenter.default.post(name: .debugNavigate, object: URL(fileURLWithPath: start))
            }
            try? await Task.sleep(for: .seconds(1.5))
            // FILEMANAGER_SNAPSHOT_KEYS="Backspace,Opt+Left": posted through the event queue, so
            // they go through KeyMonitor like real key presses.
            for chord in (ProcessInfo.processInfo.environment["FILEMANAGER_SNAPSHOT_KEYS"] ?? "")
                .split(separator: ",")
            {
                // Keys can rename and trash: only ever press them inside the demo folder.
                guard let start, let current = ActiveBrowser.shared.model?.url.path,
                    current == start || current.hasPrefix(start + "/")
                else {
                    print("snapshot: not inside FILEMANAGER_SNAPSHOT_FOLDER, not pressing \(chord)")
                    break
                }
                if chord.hasPrefix("menu:") {
                    clickMenu(String(chord.dropFirst(5)))
                } else if chord.hasPrefix("type:") {
                    typeText(String(chord.dropFirst(5)))
                } else {
                    postKey(String(chord))
                }
                try? await Task.sleep(for: .seconds(1))
            }
            capture(to: path)
            print("snapshot: windows: \(NSApp.windows.filter(\.isVisible).map(\.title))")
            print("snapshot: tabs in key window: \(NSApp.keyWindow?.tabGroup?.windows.map(\.title) ?? []), key: \(NSApp.keyWindow?.title ?? "-")")
            printMenus()
            NSApp.terminate(nil)
        }
    }

    private static func postKey(_ spelling: String) {
        // The key window, so keys reach an alert sheet when one is up.
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })
        else { return }
        var parts = spelling.split(separator: "+").map(String.init)
        let keyName = parts.removeLast()
        var flags: NSEvent.ModifierFlags = []
        for part in parts {
            switch part {
            case "Cmd": flags.insert(.command)
            case "Opt": flags.insert(.option)
            case "Ctrl": flags.insert(.control)
            case "Shift": flags.insert(.shift)
            default: break
            }
        }
        let codes: [String: UInt16] = [
            "Backspace": 51, "Delete": 117, "Return": 36, "Up": 126, "Down": 125, "Left": 123, "Right": 124,
            "F2": 120, "F4": 118, "F5": 96, "F6": 97, "Tab": 48, "Esc": 53, "Space": 49,
        ]
        // US-layout virtual key codes, so characters(byApplyingModifiers:) works as for real keys.
        let letterCodes: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
            "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
            "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, ".": 47, "[": 33, "]": 30,
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        ]
        let lower = codes[keyName] == nil ? keyName.lowercased() : ""
        let code = codes[keyName] ?? letterCodes[lower] ?? 0
        // Real Shift+letter events carry the capital letter; menus match on it.
        let chars = flags.contains(.shift) ? lower.uppercased() : lower
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
        else { return }
        NSApp.postEvent(event, atStart: false)
        print("snapshot: pressed \(spelling)")
    }

    /// "menu:New Folder" picks that menu item, as a click would (shifted synthetic key
    /// events don't match menu shortcuts the way real ones do).
    private static func clickMenu(_ title: String) {
        func find(_ menu: NSMenu) -> (NSMenu, Int)? {
            for (index, item) in menu.items.enumerated() {
                if item.title == title { return (menu, index) }
                if let sub = item.submenu, let found = find(sub) { return found }
            }
            return nil
        }
        guard let main = NSApp.mainMenu, let (menu, index) = find(main) else {
            print("snapshot: no menu item \(title)")
            return
        }
        menu.update()
        menu.performActionForItem(at: index)
        print("snapshot: chose \(title)")
    }

    /// "type:Reports" types into whatever has focus (a rename field).
    private static func typeText(_ text: String) {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            print("snapshot: nothing to type into")
            return
        }
        editor.insertText(text, replacementRange: editor.selectedRange())
        print("snapshot: typed \(text)")
    }

    private static func capture(to path: String) {
        // The key window, so a Get Info window that just opened is captured.
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
            let frameView = window.contentView?.superview
        else {
            print("snapshot: no window")
            return
        }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        frameView.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("snapshot: wrote \(path)")
    }

    private static func printMenus() {
        for item in NSApp.mainMenu?.items ?? [] {
            print("[\(item.title)]")
            for sub in item.submenu?.items ?? [] where !sub.isSeparatorItem {
                print("  \(sub.title)\(shortcut(sub))\(sub.isEnabled ? "" : " (disabled)")")
                for subsub in sub.submenu?.items ?? [] where !subsub.isSeparatorItem {
                    print("    \(subsub.title)\(shortcut(subsub))")
                }
            }
        }
    }

    private static func shortcut(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        let key: String
        switch item.keyEquivalent.unicodeScalars.first?.value {
        case 0xF700: key = "↑"
        case 0xF701: key = "↓"
        case 0xF702: key = "←"
        case 0xF703: key = "→"
        case 0x0D: key = "↩"
        default: key = item.keyEquivalent.uppercased()
        }
        return "   \(s)\(key)"
    }
}

extension Notification.Name {
    static let debugNavigate = Notification.Name("FileManagerDebugNavigate")
}
#endif
