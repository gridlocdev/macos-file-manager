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
