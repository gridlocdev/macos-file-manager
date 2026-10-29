/// Shortcuts for each action. The first chord containing Cmd is the one shown in the menu bar;
/// the app's key handler accepts all of them.
public struct Keymap: Sendable {
    public private(set) var bindings: [Action: [KeyChord]]
    private var lookup: [KeyChord: Action]

    public init(_ bindings: [Action: [KeyChord]]) {
        self.bindings = bindings
        var lookup: [KeyChord: Action] = [:]
        for action in Action.allCases {
            for chord in bindings[action] ?? [] where lookup[chord] == nil {
                lookup[chord] = action
            }
        }
        self.lookup = lookup
    }

    public func action(for chord: KeyChord) -> Action? { lookup[chord] }

    public func chords(for action: Action) -> [KeyChord] { bindings[action] ?? [] }

    public func menuChord(for action: Action) -> KeyChord? {
        chords(for: action).first { $0.modifiers.contains(.command) }
    }

    /// Chords bound to more than one action (should be empty).
    public var conflicts: [KeyChord: [Action]] {
        var seen: [KeyChord: [Action]] = [:]
        for action in Action.allCases {
            for chord in chords(for: action) { seen[chord, default: []].append(action) }
        }
        return seen.filter { $0.value.count > 1 }
    }

    public static let standard = Keymap([
        .open: [.char("o", .command), KeyChord(.down, .command), KeyChord(.returnKey, .command)],
        .newWindow: [.char("n", .command)],
        .newTab: [.char("t", .command)],
        .openInNewTab: [KeyChord(.returnKey, .control)],
        .reopenClosedTab: [.char("t", [.command, .shift])],
        .nextTab: [KeyChord(.tab, .control)],
        .previousTab: [KeyChord(.tab, [.control, .shift])],
        .showTab1: [.char("1", .command)],
        .showTab2: [.char("2", .command)],
        .showTab3: [.char("3", .command)],
        .showTab4: [.char("4", .command)],
        .showTab5: [.char("5", .command)],
        .showTab6: [.char("6", .command)],
        .showTab7: [.char("7", .command)],
        .showTab8: [.char("8", .command)],
        .showTab9: [.char("9", .command)],
        .addToSidebar: [.char("t", [.command, .control])],
        .newFolder: [.char("n", [.command, .shift])],
        .newTextFile: [.char("n", [.command, .option])],
        .rename: [KeyChord(.returnKey), KeyChord(.function(2))],
        .duplicate: [.char("d", .command)],
        .getInfo: [.char("i", .command), KeyChord(.returnKey, .option)],
        .quickLook: [KeyChord(.space)],
        .showInFinder: [],
        .showContextMenu: [KeyChord(.function(10), .shift)],
        .moveToTrash: [KeyChord(.delete, .command), KeyChord(.forwardDelete)],
        .deleteImmediately: [KeyChord(.delete, [.command, .option]), KeyChord(.forwardDelete, .shift)],
        .putBack: [],
        .undo: [.char("z", .command)],
        .redo: [.char("z", [.command, .shift])],
        .cut: [.char("x", .command)],
        .copy: [.char("c", .command)],
        .paste: [.char("v", .command)],
        .pasteMove: [.char("v", [.command, .option])],
        .copyPath: [.char("c", [.command, .shift]), .char("c", [.command, .option])],
        .selectAll: [.char("a", .command)],
        .invertSelection: [.char("i", [.command, .shift])],
        .selectByPattern: [.char("s", .command)],
        .find: [.char("f", .command)],
        .endSearch: [KeyChord(.escape)],
        .goBack: [.char("[", .command), KeyChord(.left, .option)],
        .goForward: [.char("]", .command), KeyChord(.right, .option)],
        .goUp: [KeyChord(.up, .command), KeyChord(.delete), KeyChord(.up, .option)],
        .goHome: [.char("h", [.command, .shift])],
        .goDesktop: [.char("d", [.command, .shift])],
        .goDocuments: [.char("o", [.command, .shift])],
        .goDownloads: [.char("l", [.command, .option])],
        .goApplications: [.char("a", [.command, .shift])],
        .goTrash: [],
        .focusAddressBar: [.char("l", .command), .char("d", .option)],
        .focusNextArea: [KeyChord(.function(6))],
        .focusPreviousArea: [KeyChord(.function(6), .shift)],
        .refresh: [.char("r", .command), KeyChord(.function(5))],
        .toggleHiddenFiles: [.char("h", .command), .char(".", [.command, .shift])],
        .openTerminal: [.char("t", [.command, .option]), KeyChord(.function(4))],
    ])
}
