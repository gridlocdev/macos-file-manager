#if DEBUG
import AppKit

/// `FILEMANAGER_SNAPSHOT=out.png` (debug builds): after launch, draws the front window (toolbar
/// included) into a PNG, prints the menu bar with its shortcuts, and quits. For checking the UI
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
                postKey(String(chord))
                try? await Task.sleep(for: .seconds(1))
            }
            capture(to: path)
            printMenus()
            NSApp.terminate(nil)
        }
    }

    private static func postKey(_ spelling: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
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
            "Backspace": 51, "Return": 36, "Up": 126, "Down": 125, "Left": 123, "Right": 124,
            "F4": 118, "F5": 96, "F6": 97, "Tab": 48, "Esc": 53,
        ]
        let chars = codes[keyName] == nil ? keyName.lowercased() : ""
        // Letter keys: virtual key codes for the few the snapshot needs.
        let letterCodes: [String: UInt16] = ["h": 4, "l": 37, "d": 2, "r": 15, "o": 31]
        let code = codes[keyName] ?? letterCodes[chars] ?? 0
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
        else { return }
        NSApp.postEvent(event, atStart: false)
        print("snapshot: pressed \(spelling)")
    }

    private static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
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
