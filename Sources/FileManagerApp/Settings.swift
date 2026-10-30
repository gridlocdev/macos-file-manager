import AppKit
import SwiftUI

enum SettingsKey {
    static let terminal = "terminalApp"
    static let customTerminalPath = "customTerminalPath"
    static let foldersFirst = "foldersFirst"
    static let reopenSession = "reopenSession"
    static let showPreviewPane = "showPreviewPane"
    static let showAllExtensions = "showAllExtensions"
    static let singleClickOpen = "singleClickOpen"
    static let confirmTrash = "confirmTrash"
    static let startFolder = "startFolder"
    static let customStartPath = "customStartPath"
    static let recentServers = "recentServers"

    /// Defaults for settings that start on.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [showAllExtensions: true, foldersFirst: true, reopenSession: true])
    }
}

/// The Settings window's choices, typed, for code that isn't a view (views use `@AppStorage`
/// with the same `SettingsKey`s). Reads `defaults` each time, so changes apply at once.
struct Preferences {
    var defaults: UserDefaults = .standard

    static var standard: Preferences { Preferences() }

    var showAllExtensions: Bool { defaults.bool(forKey: SettingsKey.showAllExtensions) }
    var singleClickOpen: Bool { defaults.bool(forKey: SettingsKey.singleClickOpen) }
    var confirmTrash: Bool { defaults.bool(forKey: SettingsKey.confirmTrash) }
    /// On unless turned off, even before the defaults are registered.
    var reopenSession: Bool { defaults.object(forKey: SettingsKey.reopenSession) as? Bool ?? true }

    var showPreviewPane: Bool {
        get { defaults.bool(forKey: SettingsKey.showPreviewPane) }
        nonmutating set { defaults.set(newValue, forKey: SettingsKey.showPreviewPane) }
    }

    var startFolder: StartFolder { StartFolder(rawValue: defaults.string(forKey: SettingsKey.startFolder) ?? "") ?? .home }
    var customStartPath: String? { defaults.string(forKey: SettingsKey.customStartPath) }

    var terminal: TerminalChoice {
        TerminalChoice(rawValue: defaults.string(forKey: SettingsKey.terminal) ?? "") ?? .terminal
    }
    var customTerminalPath: String? { defaults.string(forKey: SettingsKey.customTerminalPath) }
}

/// Where new windows open when there's nothing else to go on (first launch, or reopening
/// windows is off).
enum StartFolder: String, CaseIterable, Identifiable {
    case home, desktop, documents, downloads, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .custom: "Other Folder…"
        }
    }

    static func url(_ preferences: Preferences = .standard) -> URL {
        // Snapshot runs start in their demo folder, never reading Home.
        if let demo = Windows.snapshotFolder { return URL(filePath: demo) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch preferences.startFolder {
        case .home: return home
        case .desktop: return home.appendingPathComponent("Desktop")
        case .documents: return home.appendingPathComponent("Documents")
        case .downloads: return home.appendingPathComponent("Downloads")
        case .custom:
            // A folder that's gone (an unplugged disk) falls back to Home.
            guard let path = preferences.customStartPath,
                FileManager.default.fileExists(atPath: path)
            else { return home }
            return URL(filePath: path)
        }
    }
}

enum TerminalChoice: String, CaseIterable, Identifiable {
    case terminal, iTerm, ghostty, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm"
        case .ghostty: "Ghostty"
        case .custom: "Other App…"
        }
    }

    var bundleID: String? {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .custom: nil
        }
    }
}

/// Open Terminal Here: hands the folder to the terminal app chosen in Settings.
@MainActor enum TerminalLauncher {
    static func appURL() -> URL? {
        let preferences = Preferences.standard
        if let bundleID = preferences.terminal.bundleID {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
        return preferences.customTerminalPath.map { URL(fileURLWithPath: $0) }
    }

    static func open(_ folder: URL) {
        guard let app = appURL() else {
            let alert = NSAlert()
            alert.messageText = "No terminal app found"
            alert.informativeText = "Choose a terminal app in File Manager > Settings."
            alert.runModal()
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: .init()) { _, error in
            guard let error else { return }
            Task { @MainActor in NSAlert(error: error).runModal() }
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.terminal) private var terminal = TerminalChoice.terminal
    @AppStorage(SettingsKey.customTerminalPath) private var customTerminalPath = ""
    @AppStorage(SettingsKey.foldersFirst) private var foldersFirst = true
    @AppStorage(SettingsKey.reopenSession) private var reopenSession = true
    @AppStorage(SettingsKey.showAllExtensions) private var showAllExtensions = true
    @AppStorage(SettingsKey.singleClickOpen) private var singleClickOpen = false
    @AppStorage(SettingsKey.confirmTrash) private var confirmTrash = false
    @AppStorage(SettingsKey.startFolder) private var startFolder = StartFolder.home
    @AppStorage(SettingsKey.customStartPath) private var customStartPath = ""

    var body: some View {
        Form {
            Section("Files") {
                Toggle("Show folders before files", isOn: $foldersFirst).pointerCursor()
                Toggle("Show all file extensions", isOn: $showAllExtensions).pointerCursor()
                Toggle("Open items with a single click", isOn: $singleClickOpen).pointerCursor()
                Toggle("Ask before moving items to the Trash", isOn: $confirmTrash).pointerCursor()
            }
            Section("Windows") {
                Toggle("Reopen windows and tabs from last time", isOn: $reopenSession).pointerCursor()
                Picker("New windows open", selection: $startFolder) {
                    ForEach(StartFolder.allCases) { Text($0.title).tag($0) }
                }
                .pointerCursor()
                if startFolder == .custom {
                    LabeledContent("Folder") {
                        HStack {
                            Text(customStartPath.isEmpty
                                ? "None" : FileManager.default.displayName(atPath: customStartPath))
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseStartFolder).pointerCursor()
                        }
                    }
                }
            }
            Section("Keyboard") {
                LabeledContent("Shortcuts") {
                    HStack {
                        Button("Edit Shortcuts File…") { KeymapStore.shared.edit() }.pointerCursor()
                        Button("Reload") { KeymapStore.shared.reload() }.pointerCursor()
                    }
                }
                Text("Menu shortcuts change after File Manager is quit and opened again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(KeymapStore.shared.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Open Terminal Here") {
                Picker("Terminal app", selection: $terminal) {
                    ForEach(TerminalChoice.allCases) { choice in
                        Text(installedLabel(choice)).tag(choice)
                    }
                }
                .pointerCursor()
                if terminal == .custom {
                    LabeledContent("App") {
                        HStack {
                            Text(customTerminalPath.isEmpty
                                ? "None" : FileManager.default.displayName(atPath: customTerminalPath))
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseApp).pointerCursor()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    private func installedLabel(_ choice: TerminalChoice) -> String {
        guard let bundleID = choice.bundleID,
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil
        else { return choice.title }
        return "\(choice.title) (not installed)"
    }

    private func chooseStartFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            customStartPath = url.path
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            customTerminalPath = url.path
        }
    }
}
