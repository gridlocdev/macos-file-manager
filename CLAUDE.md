# macos-file-manager

macOS file manager with Explorer/Linux keybindings (SwiftPM, no Xcode project). App name in the
menu bar: "File Manager". Users: README.md and docs/. Roadmap: PLAN.md. Technical overview:
docs/Developer-Guide.md.

- Build with `xcrun swift build` / `just …`, never bare `swift` (swiftly toolchain breaks on the current SDK).
- Must stay maintainable in VS Code: no Xcode project, everything through SwiftPM and the justfile.
- Swift 6 strict concurrency, macOS 27 minimum. `BrowserModel` is `@MainActor @Observable`; folder reads run in `Task.detached`.
- Pure logic (keymap, history, paths, sorting) goes in `FileManagerCore` (no AppKit) with Swift Testing tests.
- Every command is an `Action`; shortcuts live only in `Keymap.standard`. Menus and `KeyMonitor` read it. Never add a `.keyboardShortcut` or key handler outside the keymap.
- Modifier is Cmd (where Windows/Linux use Ctrl), Opt for Alt. Return is reserved for rename; Cmd+H toggles hidden files.
- The file list is AppKit `NSTableView` (SwiftUI `Table` eats Return/Backspace). Don't switch it to SwiftUI.
- No third-party dependencies; ask before adding any.
- User docs live in `docs/` (wiki-style: `Home.md`, `_Sidebar.md`, flat hyphenated pages, relative `.md` links). Update the page describing a behaviour in the same commit that changes it. `docs/Keyboard-Shortcuts.md` must list every keymap chord (a test checks).
- Don't write anything into the user's folders (no .DS_Store-style files); app state goes in UserDefaults or Application Support.
- Never delete or overwrite user files while testing; use a scratch folder.
