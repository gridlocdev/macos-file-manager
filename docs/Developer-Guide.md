# Developer guide

File Manager is Swift 6 and SwiftUI, built with Swift Package Manager. There's no Xcode project:
you can work in VS Code, or any editor, and build from the command line. The rules in
`CLAUDE.md` at the repository root apply to everyone working on it. `PLAN.md` has the roadmap.

## Getting set up

You need Xcode (for its Swift toolchain and SDK) and [just](https://github.com/casey/just).

```bash
just build        # compile (debug)
just test         # run the unit tests
just run          # build a debug File Manager.app and open it
just run-attached # same, with logs in the terminal
just install      # release build into ~/Applications
just icons        # regenerate the app icon (needs Inkscape)
just fmt          # format with swift-format
```

Recipes call `xcrun swift`, Xcode's toolchain. A toolchain installed with swiftly can fail
against the current macOS SDK, so don't use bare `swift`.

### VS Code

Install the recommended extensions (Swift and just) when VS Code offers them, then choose the
Xcode toolchain: Command Palette → **Swift: Select Toolchain**.

- **Run and Debug** (F5 in VS Code) has *Debug FileManagerApp* and *Release FileManagerApp*.
  They run the bare executable, not the `.app` bundle. That works: `Info.plist` is embedded in
  the executable, so the menu bar still says *File Manager*, but there's no app icon and Help
  opens the repo's `docs/` instead of the bundled copy.
- **Terminal → Run Task** has `just build`, `just test`, `just run` and `just install`.
  Cmd+Shift+B builds.

## Layout

```
Sources/FileManagerCore/       pure Swift, no AppKit: unit-testable
  Action.swift                 every command: title, which menu it's in
  KeyChord.swift               a key + modifiers, and its docs spelling ("Shift+Cmd+N")
  Keymap.swift                 Action → shortcuts; the standard keymap
  NavigationHistory.swift      back/forward stacks
  PathInput.swift              address bar: resolve typed paths, Tab completion, ~ display
  FileItem.swift               a listing row, and FileSort (folders first, natural names)
  FileNaming.swift             Keep Both / Duplicate / New Folder names, name checks
  FileStep.swift               FileStep (one change), ExecutedStep (what it did), FileUndo
  TransferPlanner.swift        paste/duplicate planning: conflicts, folder merges; DiskFileTree
  FileStepExecutor.swift       runs FileSteps with FileManager (Trash injectable for tests)
Sources/FileManagerApp/        the app
  App.swift                    scenes: browser windows, Settings
  AppCommands.swift            the menu bar, built from Action + Keymap
  BrowserWindow.swift          window layout: sidebar, toolbar, address bar, list, status bar
  BrowserModel.swift           one folder view: navigation, listing, selection, perform(Action)
  FileOperations.swift         jobs with progress/cancel, conflict prompts, undo/redo, TrashLog
  Clipboard.swift              files on the system clipboard; cut state
  OperationsWindow.swift       the File Operations progress window
  DirectoryLoader.swift        background folder reads; DirectoryWatcher (live updates)
  FileListView.swift           the details list (NSTableView), icons, type-ahead
  KeyMonitor.swift             runs keymap shortcuts for a window; NSEvent → KeyChord;
                               ActiveBrowser (the key window's model, for the menu bar)
  DebugSnapshot.swift          debug-only: capture the window, print menus (just snapshot)
  SidebarView.swift            favorites and mounted volumes
  Settings.swift               settings keys, Settings window, Open Terminal Here
Tests/FileManagerCoreTests/    Swift Testing tests, including the docs check below
Resources/Info.plist           bundle info; also embedded in the executable
Resources/AppIcon.icns         app icon, generated from assets/icon.svg
assets/icon.svg                app icon source
scripts/bundle.sh              builds and signs build/File Manager.app (docs/ copied in for Help)
scripts/make-icons.sh          renders the icon (just icons)
docs/                          these pages
```

## How a shortcut runs

Every command is a case of `Action`. `Keymap.standard` lists its shortcuts. Each chord is run
by exactly one of two things:

1. **`AppCommands`**, the menu bar. Each menu item shows the action's first Cmd chord
   (`Keymap.menuChord`) and runs that chord, calling `perform` on the key window's model. These
   also work while the address bar is being edited.
2. **`KeyMonitor`**, a local `NSEvent` monitor installed per window, runs every other chord:
   plain keys like Backspace and F5, second shortcuts like Opt+Left, and keyboard-only actions
   like F6. It turns each key press into a `KeyChord`, looks it up, and calls
   `BrowserModel.perform(_:)`. It steps aside while a text field is being edited (the field
   editor is first responder), so typing a path isn't hijacked. It also maps mouse buttons 4
   and 5 to Back and Forward.

The monitor must leave menu chords alone: SwiftUI runs a menu item's shortcut even when a
monitor has swallowed the event, so handling it in both places runs the action twice.

`BrowserModel.canPerform(_:)` decides when an action is available; `perform` beeps when it
isn't. The toolbar buttons grey out, but menu items stay enabled.

The menu bar finds the key window's model through `ActiveBrowser.shared`, which `KeyMonitor`
sets when its window becomes key. (`@FocusedValue` goes nil while the AppKit file list has
focus.) SwiftUI doesn't re-evaluate menu items when that model's properties change, so:

- don't disable menu items from model state: a stale disabled item swallows its shortcut;
- keep menu titles fixed, and use buttons, not `Toggle`s: a stale menu `Toggle` writes its
  old value back.

### Adding a shortcut or action

1. Add a case to `Action` with its `title` and `menu`.
2. Add its chords to `Keymap.standard`.
3. Handle it in `BrowserModel.perform` (and `canPerform` if it isn't always available).
4. Put it in a menu in `AppCommands`.
5. Add a row to `docs/Keyboard-Shortcuts.md` whose first cell is the title and second cell lists
   every chord in `KeyChord.description` spelling (modifiers in the order Ctrl, Opt, Shift, Cmd).
   `KeymapTests.shortcutsPageMatchesKeymap` fails until the page matches.

`KeymapTests.noChordIsBoundTwice` catches clashes.

## File operations

Every change to files is a list of `FileStep`s (copy, move, create, trash, delete) run by
`FileStepExecutor`, and nothing else touches the file system. That gives undo for free:

1. The executor returns `ExecutedStep`s: what actually happened, including the name the Trash
   chose.
2. `FileUndo.inverse(of:)` turns those into the steps that reverse them (copies and new items go
   to the Trash rather than being deleted). Permanent deletes have no inverse.
3. Running an undo produces executed steps too, and their inverse is the redo.

`FileOperations` (app target) wraps this: each run is a `FileJob` on a detached task with
progress and Cancel, pushed onto one app-wide undo stack (like Explorer). It also writes
`TrashLog` (`~/Library/Application Support/File Manager/trash-log.json`), which maps Trash paths
to original paths for Put Back; macOS doesn't share Finder's own record.

Paste and duplicate go through `TransferPlanner`, which is pure (it reads through the `FileTree`
protocol): first `conflicts(…)` lists the clashes, the app asks about each (Replace / Keep Both /
Skip / Stop, with "do this for the rest"), then `plan(…)` produces the steps. Folders with the
same name merge; Replace trashes the existing item first; copying into the same folder
duplicates. The planner tests use an in-memory `FakeTree`; the executor tests run in a temp
folder with a fake Trash.

Text editing wins over file actions: `AppCommands.run` sends Cut/Copy/Paste/Undo/Redo/Select All
(and Cmd+Backspace as "delete to line start") to the text field when one is being edited, and
ignores other file actions. `KeyMonitor` only lets Return, F2 and forward Delete act on files
when the list (`FileTableView`) has focus.

Rename edits the name cell in place (`FileListView.Coordinator.beginRename`). The list holds
back reloads while the field is open, since a reload would throw the edit away.

## The file list

`FileListView` wraps an `NSTableView`, because SwiftUI's `Table` takes Return and Backspace for
itself, has weak type-ahead, and gets slow on large folders. `BrowserModel` bumps
`listingVersion` whenever `items` changes; the table reloads only then. Selection syncs both
ways (`isUpdating` stops the loop). Column widths and order are saved by AppKit under the
autosave name `FileList`.

`DirectoryLoader` reads a folder with `contentsOfDirectory(at:includingPropertiesForKeys:)` in a
detached task, prefetching the values the columns need. `DirectoryWatcher` watches the folder's
file descriptor for writes, renames and deletes and refreshes after 150 ms of quiet. It only
sees entries added, removed or renamed, not edits inside files.

## Tests

`just test` runs Swift Testing suites for everything in `FileManagerCore`: keymap lookups and
conflicts, history, path resolution and completion, and sorting. Put new pure logic in
`FileManagerCore` and test it there; keep AppKit in the app target.

### Snapshots

Debug builds have a hook (`DebugSnapshot.swift`) that draws the window into a PNG, prints the
whole menu bar with shortcuts and enabled state, and quits. It works without screen-recording
permission, so it's also how the docs screenshot is made:

```bash
just snapshot                                    # build/snapshot.png of a demo folder
just snapshot "Backspace,Opt+Left,Cmd+H" out.png # press keys first, then capture
just snapshot "menu:New Folder,type:Reports,Return,Cmd+Z" out.png
```

Steps are key chords, `menu:<item title>` and `type:<text>`. Keys go through the normal event
queue, so they exercise `KeyMonitor` and the menu bar like real key presses. Shifted Cmd
shortcuts (Shift+Cmd+N) don't match menus when synthesized; use `menu:` for those. The demo
folder (`build/snapshot-demo`) is recreated each run, and the hook refuses to press anything
once the window has left it, so a test can't touch real files. Undoing a copy or a new folder
moves it to the real Trash. The app is launched with `open`, so it becomes the active app; Cmd shortcuts only
reach the menu bar of the active app.

## App icon

The icon is drawn by hand in `assets/icon.svg`: a white standing set of drawers on an amber
gradient tile, on Apple's 1024 icon grid (an 824-unit tile at 100,100 with a transparent
margin). The gaps and handles use the tile's gradient so they read as cut out of the cabinet.

After editing the SVG, run `just icons` (needs Inkscape: `brew install --cask inkscape`). It
regenerates `assets/icon/` and `Resources/AppIcon.icns`, which are committed so builds don't
need Inkscape.

## Signing

`scripts/bundle.sh` signs with the first Apple Development or Developer ID identity in your
keychain, or ad hoc (`-`) if there isn't one. Override with `SIGN_IDENTITY="…" just install`.
With ad-hoc signing, macOS may treat each rebuild as a new app and ask for folder access again.
