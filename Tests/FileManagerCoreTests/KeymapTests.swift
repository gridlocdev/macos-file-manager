import Foundation
import Testing

@testable import FileManagerCore

@Suite struct KeymapTests {
    let keymap = Keymap.standard

    @Test func noChordIsBoundTwice() {
        #expect(keymap.conflicts.isEmpty, "\(keymap.conflicts)")
    }

    /// Put Back, Trash and Show in Finder are menu-only, as in Finder.
    @Test func everyOtherActionHasAShortcut() {
        for action in Action.allCases where ![.putBack, .goTrash, .showInFinder].contains(action) {
            #expect(!keymap.chords(for: action).isEmpty, "\(action) has no shortcut")
        }
    }

    @Test func fileShortcuts() {
        #expect(keymap.action(for: KeyChord(.returnKey)) == .rename)
        #expect(keymap.action(for: KeyChord(.function(2))) == .rename)
        #expect(keymap.action(for: KeyChord(.forwardDelete)) == .moveToTrash)
        #expect(keymap.menuChord(for: .moveToTrash) == KeyChord(.delete, .command))
        #expect(keymap.action(for: KeyChord(.forwardDelete, .shift)) == .deleteImmediately)
        #expect(keymap.action(for: .char("v", [.command, .option])) == .pasteMove)
        #expect(keymap.action(for: KeyChord(.space)) == .quickLook)
        #expect(keymap.action(for: KeyChord(.returnKey, .option)) == .getInfo)
        #expect(keymap.action(for: KeyChord(.function(10), .shift)) == .showContextMenu)
    }

    @Test func textEditingFallbacks() {
        #expect(Action.copy.textSelector == "copy:")
        #expect(Action.moveToTrash.textSelector == "deleteToBeginningOfLine:")
        #expect(Action.duplicate.actsOnFiles && Action.duplicate.textSelector == nil)
        #expect(!Action.goBack.actsOnFiles)
    }

    @Test func looksUpExplorerAndLinuxKeys() {
        #expect(keymap.action(for: KeyChord(.delete)) == .goUp)
        #expect(keymap.action(for: KeyChord(.up, .option)) == .goUp)
        #expect(keymap.action(for: KeyChord(.left, .option)) == .goBack)
        #expect(keymap.action(for: .char("d", .option)) == .focusAddressBar)
        #expect(keymap.action(for: KeyChord(.function(5))) == .refresh)
        #expect(keymap.action(for: .char("h", .command)) == .toggleHiddenFiles)
        #expect(keymap.action(for: KeyChord(.returnKey, .command)) == .open)
    }

    @Test func menuShowsTheFirstCommandChord() {
        #expect(keymap.menuChord(for: .open) == .char("o", .command))
        #expect(keymap.menuChord(for: .goUp) == KeyChord(.up, .command))
        #expect(keymap.menuChord(for: .focusNextArea) == nil)
    }

    @Test func docsSpelling() {
        #expect(KeyChord.char("n", [.command, .shift]).description == "Shift+Cmd+N")
        #expect(KeyChord(.function(5)).description == "F5")
        #expect(KeyChord(.delete).description == "Backspace")
    }

    /// docs/Keyboard-Shortcuts.md lists every action with all of its keys, so the page can't
    /// drift from the keymap.
    @Test func shortcutsPageMatchesKeymap() throws {
        let page = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/Keyboard-Shortcuts.md")
        let text = try String(contentsOf: page, encoding: .utf8)
        let rows = text.split(separator: "\n").map(String.init).filter { $0.hasPrefix("|") }
        for action in Action.allCases {
            let row = rows.first { cells($0).first == action.title }
            #expect(row != nil, "No row titled \"\(action.title)\"")
            guard let row else { continue }
            let keys = cells(row).dropFirst().first ?? ""
            for chord in keymap.chords(for: action) {
                #expect(keys.contains(chord.description), "\(action.title): \(chord) missing")
            }
        }
    }

    private func cells(_ row: String) -> [String] {
        row.split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "")
        }
    }
}
