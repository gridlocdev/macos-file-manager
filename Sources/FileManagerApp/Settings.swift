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

    /// Defaults for settings that start on.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [showAllExtensions: true, foldersFirst: true, reopenSession: true])
    }
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

    static var url: URL {
        // Snapshot runs start in their demo folder, never reading Home.
        if let demo = Windows.snapshotFolder { return URL(filePath: demo) }
        let defaults = UserDefaults.standard
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch StartFolder(rawValue: defaults.string(forKey: SettingsKey.startFolder) ?? "") ?? .home {
        case .home: return home
        case .desktop: return home.appendingPathComponent("Desktop")
        case .documents: return home.appendingPathComponent("Documents")
        case .downloads: return home.appendingPathComponent("Downloads")
        case .custom:
            // A folder that's gone (an unplugged disk) falls back to Home.
            guard let path = defaults.string(forKey: SettingsKey.customStartPath),
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
        let defaults = UserDefaults.standard
        let choice = TerminalChoice(rawValue: defaults.string(forKey: SettingsKey.terminal) ?? "") ?? .terminal
        if let bundleID = choice.bundleID {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
        return defaults.string(forKey: SettingsKey.customTerminalPath).map { URL(fileURLWithPath: $0) }
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
                Toggle("Show folders before files", isOn: $foldersFirst)
                Toggle("Show all file extensions", isOn: $showAllExtensions)
                Toggle("Open items with a single click", isOn: $singleClickOpen)
                Toggle("Ask before moving items to the Trash", isOn: $confirmTrash)
            }
            Section("Windows") {
                Toggle("Reopen windows and tabs from last time", isOn: $reopenSession)
                Picker("New windows open", selection: $startFolder) {
                    ForEach(StartFolder.allCases) { Text($0.title).tag($0) }
                }
                if startFolder == .custom {
                    LabeledContent("Folder") {
                        HStack {
                            Text(customStartPath.isEmpty
                                ? "None" : FileManager.default.displayName(atPath: customStartPath))
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseStartFolder)
                        }
                    }
                }
            }
            Section("Keyboard") {
                LabeledContent("Shortcuts") {
                    HStack {
                        Button("Edit Shortcuts File…") { KeymapStore.shared.edit() }
                        Button("Reload") { KeymapStore.shared.reload() }
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
                if terminal == .custom {
                    LabeledContent("App") {
                        HStack {
                            Text(customTerminalPath.isEmpty
                                ? "None" : FileManager.default.displayName(atPath: customTerminalPath))
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseApp)
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
