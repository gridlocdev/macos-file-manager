# macos-file-manager

macOS file manager with Explorer/Linux keybindings (SwiftPM, no Xcode project). App name in the
menu bar: "File Manager". Users: README.md and docs/. Technical overview:
docs/development.md and docs/architecture.md.

- Build with `xcrun swift build` / `just …`, never bare `swift` (swiftly toolchain breaks on the current SDK).
- Must stay maintainable in VS Code: no Xcode project, everything through SwiftPM and the justfile.
- Swift 6 strict concurrency, macOS 27 minimum. `BrowserModel` is `@MainActor @Observable`; folder reads run in `Task.detached`.
- Pure logic (keymap, history, paths, sorting) goes in `FileManagerCore` (no AppKit) with Swift Testing tests.
  Model behaviour that needs the app target is tested in `FileManagerAppTests` with a `Sandbox`
  (scratch folder, own UserDefaults suite, fake Trash); pass dependencies in through
  `BrowserServices` rather than reaching for `.shared`.
- Every command is an `Action`; shortcuts live only in `Keymap.standard`. Menus and `KeyMonitor` read it through `KeymapStore` (which layers the user's Shortcuts.json on top). Never add a `.keyboardShortcut` or key handler outside the keymap. `docs/custom-shortcuts.md` must list every action name (a test checks).
- Modifier is Cmd (where Windows/Linux use Ctrl), Opt for Alt. Return is reserved for rename; Cmd+H toggles hidden files.
- The file list is AppKit `NSTableView` (SwiftUI `Table` eats Return/Backspace). Don't switch it to SwiftUI.
- No third-party dependencies; ask before adding any.
- Docs live in `docs/`: lowercase kebab-case pages with relative `.md` links, indexed by `docs/README.md` (list a new page there), and the README stays a short front page. The Help menu opens `docs/README.md` and `docs/controls.md`, so don't rename those. Update the page describing a behaviour in the same commit that changes it. `docs/controls.md` must list every keymap chord (a test checks).
- Every file change goes through `FileStep`s run by `FileStepExecutor` (via `FileOperations`), so it's undoable and shows progress. Never call FileManager copy/move/remove elsewhere. Replace trashes rather than deletes.
- Tabs are native window tabs; each tab is a `WindowGroup(for: WindowSpec.self)` window with its own `BrowserModel` (see `Windows.swift`). Keep `BrowserModel.init` free of work.
- SwiftUI gotchas seen here: menu items don't refresh from model state (keep them enabled, fixed titles, no Toggles); `DisclosureGroup` builds closed content (guard with `isExpanded`); only write observed state on real changes. `.onHover` never fires in the toolbar: use `onMouseOver` (Hover.swift).
- Every clickable SwiftUI control (button, menu, picker, toggle, sidebar row) gets `.pointerCursor()`.
- Test file operations only in `build/snapshot-demo` (`just snapshot`); never against real folders.
- Testing must not bring up macOS folder-access prompts (Desktop, Documents, Downloads, Pictures, iCloud, network/removable disks): every new build counts as a new app. Snapshot runs start in the demo folder, root the sidebar tree there and skip disks; keep it that way. Never launch the built app outside a snapshot run (e.g. `open -a` when no snapshot instance is running starts a normal one that reads Home and your session).
- Don't write anything into the user's folders (no .DS_Store-style files); app state goes in UserDefaults or Application Support.
- Never delete or overwrite user files while testing; use a scratch folder.
