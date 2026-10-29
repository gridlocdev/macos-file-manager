import AppKit
import FileManagerCore
import Observation

/// The keymap in use: the standard one with your shortcuts file on top
/// (~/Library/Application Support/File Manager/Shortcuts.json). Read at launch and on Reload.
@MainActor @Observable
final class KeymapStore {
    static let shared = KeymapStore()

    private(set) var keymap = Keymap.standard
    /// What couldn't be used from the file (and shortcuts that moved), for Settings.
    private(set) var problems: [String] = []
    let file: URL

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("File Manager/Shortcuts.json")
        reload()
    }

    func reload() {
        // Snapshot runs and tests use the standard shortcuts.
        guard !Windows.isSnapshotRun, let data = try? Data(contentsOf: file) else {
            keymap = .standard
            problems = []
            return
        }
        guard let overrides = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            keymap = .standard
            problems = ["Shortcuts.json isn't valid: it should map action names to lists of shortcuts."]
            return
        }
        (keymap, problems) = Keymap.standard.applying(overrides)
    }

    /// Opens the file in your text editor, writing a starter file first if there isn't one.
    func edit() {
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Self.starter.write(to: file, atomically: true, encoding: .utf8)
        }
        let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        if let editor {
            NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    /// Names starting with "_" are ignored, so the examples do nothing until renamed.
    static let starter = """
        {
          "_about": ["Each action gets exactly the shortcuts listed; [] removes them.",
                     "Remove the _ from an example to use it. Action names: Custom-Shortcuts in the docs.",
                     "Then choose Reload in File Manager > Settings > Keyboard."],
          "_rename": ["F2"],
          "_compress": ["Ctrl+Cmd+Z"],
          "_goUp": ["Cmd+Up", "Backspace", "Opt+Up"]
        }

        """
}
