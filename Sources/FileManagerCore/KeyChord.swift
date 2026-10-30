/// A key plus modifiers, independent of AppKit so the keymap can be tested.
public struct KeyChord: Hashable, Sendable, CustomStringConvertible {
    public enum Key: Hashable, Sendable {
        /// A printable key as typed without modifiers, lowercased ("n", ".", "[").
        case character(String)
        case returnKey, delete, forwardDelete, tab, space, escape
        case up, down, left, right
        case function(Int)
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var key: Key
    public var modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public static func char(_ c: String, _ modifiers: Modifiers = []) -> KeyChord {
        KeyChord(.character(c.lowercased()), modifiers)
    }

    /// What an arrow chord does in a text field ("moveToBeginningOfDocument:" for Cmd+Up), for
    /// a menu shortcut pressed while text is being edited. Nil for other chords.
    public var textSelector: String? {
        let move: String
        switch (key, modifiers.subtracting(.shift)) {
        case (.up, .command): move = "moveToBeginningOfDocument"
        case (.down, .command): move = "moveToEndOfDocument"
        case (.left, .command): move = "moveToLeftEndOfLine"
        case (.right, .command): move = "moveToRightEndOfLine"
        case (.up, .option): move = "moveToBeginningOfParagraph"
        case (.down, .option): move = "moveToEndOfParagraph"
        case (.left, .option): move = "moveWordLeft"
        case (.right, .option): move = "moveWordRight"
        case (.up, []): move = "moveUp"
        case (.down, []): move = "moveDown"
        case (.left, []): move = "moveLeft"
        case (.right, []): move = "moveRight"
        default: return nil
        }
        return move + (modifiers.contains(.shift) ? "AndModifySelection:" : ":")
    }

    /// The spelling used in the docs, e.g. "Cmd+Shift+N", "Opt+Up", "F5".
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    private var keyName: String {
        switch key {
        case .character(let c): c.uppercased()
        case .returnKey: "Return"
        case .delete: "Backspace"
        case .forwardDelete: "Delete"
        case .tab: "Tab"
        case .space: "Space"
        case .escape: "Esc"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .function(let n): "F\(n)"
        }
    }
}

extension KeyChord {
    /// Reads a chord written the way the docs write them: "Shift+Cmd+N", "Opt+Up", "F5", "Cmd+=".
    /// Modifiers in any order; Command/⌘, Option/Alt/⌥, Control/⌃ and Enter/Escape work too.
    /// Case doesn't matter.
    public init?(parsing text: String) {
        var parts = text.trimmingCharacters(in: .whitespaces).split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // "Cmd++" is Cmd and the + key.
        if parts.count >= 2, parts.suffix(2) == ["", ""] { parts = parts.dropLast(2) + ["+"] }
        guard let keyName = parts.popLast(), !keyName.isEmpty else { return nil }
        var modifiers: Modifiers = []
        for part in parts {
            switch part.lowercased() {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "shift", "⇧": modifiers.insert(.shift)
            default: return nil
            }
        }
        let key: Key
        switch keyName.lowercased() {
        case "return", "enter": key = .returnKey
        case "backspace": key = .delete
        case "delete", "del": key = .forwardDelete
        case "tab": key = .tab
        case "space": key = .space
        case "esc", "escape": key = .escape
        case "up": key = .up
        case "down": key = .down
        case "left": key = .left
        case "right": key = .right
        case let name where name.count >= 2 && name.first == "f" && Int(name.dropFirst()) != nil:
            guard let n = Int(name.dropFirst()), (1...20).contains(n) else { return nil }
            key = .function(n)
        case let name where name.count == 1:
            key = .character(name)
        default:
            return nil
        }
        self.init(key, modifiers)
    }
}
