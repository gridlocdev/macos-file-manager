import AppKit
import SwiftUI

enum SettingsKey {
    static let terminal = "terminalApp"
    static let customTerminalPath = "customTerminalPath"
    static let foldersFirst = "foldersFirst"
    static let reopenSession = "reopenSession"
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

    var body: some View {
        Form {
            Section("Files") {
                Toggle("Show folders before files", isOn: $foldersFirst)
            }
            Section("Windows") {
                Toggle("Reopen windows and tabs from last time", isOn: $reopenSession)
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
