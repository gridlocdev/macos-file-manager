# Developer guide

File Manager is Swift 6 and SwiftUI, built with Swift Package Manager. There's no Xcode project:
you can work in VS Code, or any editor, and build from the command line. The rules in
`CLAUDE.md` at the repository root apply to everyone working on it.

## Getting set up

You need Xcode (for its Swift toolchain and SDK) and [just](https://github.com/casey/just).

```bash
just build        # compile (debug)
just test         # run the unit tests
just run          # build a debug File Manager.app and open it
just run-attached # same, with logs in the terminal
just install      # release build into ~/Applications
just dist         # release build zipped as build/File-Manager-<version>.zip
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
  ActionAvailability.swift     when each Action is available (ActionState: selection, tabs, clipboard…)
  KeyChord.swift               a key + modifiers, and its docs spelling ("Shift+Cmd+N")
  Keymap.swift                 Action → shortcuts; the standard keymap
  NavigationHistory.swift      back/forward stacks; each page can carry what was showing when it
                               was left (BrowserModel.SavedPage: an open search's snapshot, the
                               selection, the scroll position), handed back by Back/Forward
  PathInput.swift              address bar: resolve typed paths, Tab completion, ~ display
  FileItem.swift               a listing row, and FileSort (folders first, natural names)
  FileNaming.swift             Keep Both / Duplicate / New Folder names, name checks
  FileStep.swift               FileStep (one change), ExecutedStep (what it did), FileUndo
  TransferPlanner.swift        paste/duplicate planning: conflicts, folder merges; DiskFileTree;
                               ConflictQuestions (ask each, or one answer for the rest)
  UndoHistory.swift            the app-wide undo/redo stacks of file operations
  CommandLog.swift             numbered one-shot requests from a model to its views
  FileStepExecutor.swift       runs FileSteps with FileManager (Trash injectable for tests)
  DropRules.swift              drag-and-drop move/copy rules; FolderSize; Permissions
  Navigation.swift             Breadcrumbs, RecentFolders, PinnedFolders, SessionState
  Search.swift                 NamePattern (wildcards, Spotlight predicate), SearchCriteria, Selection
  BatchRename.swift            batch rename options, preview with problems, moves (swaps via temp names)
  ServerAddress.swift          Connect to Server addresses (smb, \\server\share, nfs, WebDAV); recents
  Archive.swift                zip names; compress/extract with ditto (run by FileStepExecutor)
  ViewSettings.swift           FolderView (mode, sort, groups, zoom), FolderViewMemory, Grouping, ListRow
  FilePaths.swift              URL identity: normalized, canonical, isSameFile, isInside, isTrashFolder,
                               isGuardedFolder; realPath and isSameItem (read the disk: symlinks, case)
  FolderAccess.swift           FolderAccessHelp: which System Settings switch unblocks a folder (EPERM)
  FocusCycle.swift             F6 / Shift+F6 order: list → (right list) → address bar → sidebar
Sources/FileManagerApp/        the app
  App.swift                    scenes: browser windows, Settings
  AppCommands.swift            the menu bar, built from Action + Keymap
  BrowserWindow.swift          window layout: sidebar, toolbar, panes (split view), status bars
  BrowserModel.swift           one folder view: navigation, filter/sort, selection, perform(Action)
  PaneCommand.swift            what a model asks its views to do once; .onPaneCommand
  BrowserServices.swift        the shared objects a BrowserModel is given (operations, windows, stores, clipboard)
  FolderListing.swift          a folder as read from disk: items, error, free space, watcher
  SearchSession.swift          Find for one pane: criteria, scope, subfolder search results
  BrowserPresenter.swift       what the model asks the user (confirm, problems, pattern); NSAlert version
  WindowControls.swift         a pane's window for the model: tabs, where the focus is, the sidebar
  FileOperations.swift         jobs with progress/cancel, conflict prompts, undo/redo, TrashLog
  Clipboard.swift              files on the system clipboard; cut state
  OperationsWindow.swift       the File Operations progress window
  FileListInteractions.swift   FileTableView (spring loading, Quick Look, Services); drag and
                               drop and the right-click menu for the list
  InfoWindow.swift             Get Info windows (one per selection)
  Windows.swift                WindowSpec; every window/tab, tab joining, closed tabs, session
  AddressBar.swift             address bar: path segments with › menus, or a text field; VolumeNames
  SidebarView.swift            pinned, recent, locations (eject), folder tree; drop targets
  SidebarStore.swift           pinned and recent folders in UserDefaults
  DirectoryLoader.swift        background folder reads; DirectoryWatcher (live updates)
  SearchBar.swift              the find bar (Cmd+F): text, This Folder/Subfolders, filters
  FolderSearch.swift           subfolder search: Spotlight + a folder walk, merged, in batches
  BatchRenameView.swift        the batch rename sheet with its live preview
  FileListView.swift           the details list (NSTableView): columns, group rows, zoom, column chooser
  FileIconView.swift           the icon view (NSCollectionView), thumbnails, Cmd+scroll zoom, type-ahead
  SpringLoading.swift          springLoaded(into:): hold a drag on a breadcrumb or Back/Forward to go there
  FileViewSupport.swift        shared by both views: InlineRename, IconCache (one, app-wide), FileDrop, FileFormat
  Hover.swift                  onMouseOver (an AppKit tracking area: .onHover never fires in the toolbar),
                               pointerCursor() for every clickable SwiftUI control, SidebarHover,
                               fadedDragImage() (a pinned row's drag shows the row, faded: it patches
                               the SwiftUI list class's draggingSession(_:willBeginAt:) and draws the
                               row with ImageRenderer, since a snapshot loses the vibrant colours)
  FileContextMenu.swift        the right-click menu for both views
  QuickLook.swift              FileBrowsingView (either view has focus) and the Quick Look panel source
  PreviewPane.swift            the docked preview (Opt+P)
  FolderViewStore.swift        each folder's view, saved in Application Support
  KeymapStore.swift            the keymap in use: standard + Shortcuts.json overrides; menuKeymap
  ConnectToServer.swift        the Connect to Server sheet; NetFS mounting
  KeyMonitor.swift             runs keymap shortcuts for a window; NSEvent → KeyChord;
                               ActiveBrowser (the key window's model, for the menu bar)
  DebugSnapshot.swift          debug-only: capture the window, print menus (just snapshot)
  Settings.swift               settings keys, Preferences (typed reads for non-view code),
                               Settings window, Open Terminal Here
Tests/FileManagerCoreTests/    Swift Testing tests, including the docs check below
Tests/FileManagerAppTests/     BrowserModel, FileOperations, Windows, FolderSearch in a Sandbox (scratch folder and stores)
Resources/Info.plist           bundle info; also embedded in the executable
Resources/AppIcon.icns         app icon, generated from assets/icon.svg
assets/icon.svg                app icon source
scripts/bundle.sh              builds and signs build/File Manager.app (docs/ copied in for Help)
scripts/make-icons.sh          renders the icon (just icons)
.github/workflows/             CI (build and test) and releases (on a v* tag)
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
monitor has swallowed the event, so handling it in both places runs the action twice. Menus
don't pick up Reload in Settings, so `KeymapStore` keeps `menuKeymap`, the keymap at launch: the
menu bar is built from it, the monitor leaves exactly its menu chords alone, and every other
chord comes from the reloaded `keymap`. `Keymap.overrides(fromJSON:)` reads Shortcuts.json entry
by entry, so one bad entry is reported without dropping the rest.

`KeyChord(event)` reads a character key with Cmd applied when it's held (never Shift), so
layouts with a Command layer (AZERTY's digits, Dvorak-QWERTY⌘) match as macOS menus do.

`Action.isAvailable(in:)` (Core) decides when an action is available, from an `ActionState`
that `BrowserModel` provides; `BrowserModel.canPerform(_:)` asks it, and `perform` beeps when it
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
3. Handle it in `BrowserModel.perform`, and say when it's available in `Action.isAvailable(in:)`
   (the switch lists every case, so it won't compile until you do).
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

Moves out of the Trash (undoing a trash, Put Back) are `.restore` steps, whose inverse trashes
the item again, so a redo of Move to Trash goes through the Trash and the `TrashLog`. A copy is
recorded only if its destination exists (finished, cut short by Cancel, or failed partway).
`Outcome.stepsRun` says how far a run got: an undo or redo that stops partway puts the steps it
didn't reach back on its stack (`UndoHistory.putBack`). Undo and redo wait until no job is
running, and a job leaves the list only once its undo is recorded, so they run one at a time
and Cmd+Z during a copy undoes that copy.

`FileOperations` (app target) wraps this: each run is a `FileJob` on a detached task with
progress (an `AsyncStream`, so it arrives in order) and Cancel (checked between steps, and
between the items of a folder being copied; a single large file still copies to the end), pushed onto one app-wide `UndoHistory` (like Explorer). Tags it sets are
posted as a `TagsChanged` message, which every `BrowserModel` observes. It also writes
`TrashLog` (`~/Library/Application Support/File Manager/trash-log.json`), which maps Trash paths
to original paths for Put Back; macOS doesn't share Finder's own record.

Paste and duplicate go through `TransferPlanner`, which is pure (it reads through the `FileTree`
protocol): first `planAsking(…)` lists the clashes, with the plan made meanwhile (final when
there are none, so a paste without clashes walks its sources once); the app asks about each
(Replace / Keep Both / Skip / Stop, with "do this for the rest"), then `plan(…)` produces the
steps. `ConflictQuestions.answers` does the asking, keyed by the whole conflict (two items can
land on one name); `transfer` takes an `ask` closure in place of the alerts. "Into itself" and
"already in this folder" compare with `FileTree.isSameItem` up the folder's `realPath`, so a
symlink or other case doesn't get past them; `DropRules` takes the same check. Folders with the
same name merge; Replace trashes the existing item first; copying into the same folder
duplicates. The planner tests use an in-memory `FakeTree`; the executor tests run in a temp
folder with a fake Trash.

Text editing wins over file actions: `AppCommands.run` sends Cut/Copy/Paste/Undo/Redo/Select All
(and Cmd+Backspace as "delete to line start") to the text field when one is being edited, sends
an arrow chord such as Cmd+Up (Go Up) as its cursor movement (`KeyChord.textSelector`), and
ignores other file actions. `KeyMonitor` only lets Return, F2 and forward Delete act on files
when the list (`FileTableView`) has focus.

Rename edits the name cell in place (`FileListView.Coordinator.beginRename`). The list holds
back reloads while the field is open, since a reload would throw the edit away.

## Drag and drop, right-click menu, Quick Look

- **Drag out**: the table's data source writes each row's file URL to the pasteboard, so Finder
  and other apps get real files.
- **Drop in**: `validateDrop` retargets to the whole table unless the pointer is over a folder
  row, and asks `DropRules.operation` (pure, tested) for move/copy from the modifier keys and
  whether source and target share a `volumeIdentifier`. Accepting a drop calls
  `BrowserModel.drop`, which goes through `FileOperations.transfer` like Paste, so conflicts,
  merging and undo all work. Sidebar rows use SwiftUI `dropDestination` with the same rules.
- **Spring-loaded folders**: `FileTableView` adopts `NSSpringLoadingDestination` and navigates
  into the folder row under the pointer. Breadcrumbs and Back/Forward use `springLoaded(into:)`
  (SpringLoading.swift): a SwiftUI `DropDelegate` that runs an action after a second's hold
  (Back/Forward repeat it) and drops into a folder, or refuses the drop when given none. It
  reads the files from the drag pasteboard (`FileDrop.draggedFiles`), since SwiftUI hands a
  delegate item providers rather than the dragging info.
- **Scrolling while dragging**: `FileTableView` and `FileCollectionView` pass `draggingUpdated`
  to a `DragAutoscroll` (FileViewSupport.swift), which scrolls the enclosing scroll view after
  1.5 s within 40 pt of the top (below the header inset) or bottom, at the Settings speed.
- **Right-click menu**: `table.menu` with the coordinator as `NSMenuDelegate`;
  `menuNeedsUpdate` builds an item menu or a folder menu from `Action`s, plus Open With
  (`NSWorkspace.urlsForApplications(toOpen:)`; the folder menu's opens the folder itself) and Share (`standardShareMenuItem`). Shift+F10
  pops the same menu under the first selected row. Services come from `FileTableView` being an
  `NSServicesMenuRequestor` for file URLs.
- **Quick Look**: `FileTableView` takes control of `QLPreviewPanel` and is its data source;
  selection changes reload the panel (including ones the model makes, applied in
  `applySelection`), and key presses in the panel are forwarded to the table.
- **Get Info**: `BrowserModel.perform(.getInfo)` sends `.getInfo(urls)`; `BrowserWindow`
  opens a `WindowGroup(for: [URL].self)` window. Folder and package sizes come from
  `FolderSize.measure` in a detached task, cancelled with the window's task (`inBackground`), so
  it stops when the window closes.

Synthetic events can't drive drags or menus, so `just snapshot` doesn't cover these; check them
by hand.

## Pane commands

The model asks its views for one-off things (focus the list or address bar, start renaming,
toggle Quick Look, show the right-click menu, open a window, split) with
`BrowserModel.send(_: PaneCommand)`. Commands go into a numbered `CommandLog` (Core): SwiftUI
views take them with `.onPaneCommand(model) { … }`, the file list and icon view with
`model.takeFileViewCommands()`. Each remembers the last number it handled, so two commands in
a row both arrive and a view that appears later doesn't replay old ones. The file views' place
is kept on the model, so switching between icons and details doesn't lose a command sent
while the new view was being made (the focus, usually). Add a
case to `PaneCommand` rather than a counter on the model.

## Windows and tabs

Tabs are native window tabs: every tab is a window from `WindowGroup(for: WindowSpec.self)`
with its own `BrowserModel`. A `WindowSpec` carries a fresh id (so SwiftUI never reuses a
window), the folder, and optionally `tabParent`, the model id of the window to join.

`Windows` (app target) registers each model when its view appears and when its window
exists, in either order, then calls `addTabbedWindow` on the parent's last tab. While
restoring, tabs can appear before their parent; they wait in `waiting` until it does.

`BrowserModel` can't call `openWindow`, so it sends `.open(spec)` (`requestOpen`) and
`BrowserWindow` opens them. With no window open, folders sent from other apps are opened
through `Windows.openWindow`, which the menu bar (`AppCommands`, alive without windows) sets
from SwiftUI's `openWindow`. When a window or split pane closes, `BrowserModel.stop()` ends its
loading, watching and searching; file operations it started carry on. `BrowserModel.init` does no work, because SwiftUI may create throwaway copies when
it re-creates `BrowserWindow`; loading starts in `start()` from `onAppear`.

Session restore: `Windows.save()` groups windows by `tabGroup` (minimized ones, and all of them
while the app is hidden, count as open) and stores a `SessionState` in
UserDefaults (debounced on every change, and in `applicationShouldTerminate` while windows
are still open). At launch the WindowGroup's `defaultValue` is the first saved tab; the first
window then opens the rest. SwiftUI's own restoration is off (`.restorationBehavior(.disabled)`).
Snapshot runs never read or save the session unless `FILEMANAGER_SNAPSHOT_RESTORE` is set.

Ctrl+Tab and Ctrl+Shift+Tab are switched by macOS itself even when the key handler has
consumed them, so `Action.isHandledByMacOS` makes `KeyMonitor` pass them on (handling them too
switched twice and looked like nothing happened).

## Sidebar

The sidebar's folder tree uses `DisclosureGroup`s that only build their children while open:
`DisclosureGroup` builds its content even when closed, and every closed child listing its own
children walked the whole disk and starved the main thread. `FolderTree.expanded` is only
written when it actually changes, since any write to an observed property re-renders. A
folder's subfolders are read in the background and appear when they're in (`children` is
written only when a list changes). The disks in Locations are read when the sidebar appears and
on mount and unmount, not as `@State`'s initial value, which runs on every redraw.

## The file list

`FileListView` wraps an `NSTableView`, because SwiftUI's `Table` takes Return and Backspace for
itself, has weak type-ahead, and gets slow on large folders. `BrowserModel` bumps
`listingVersion` whenever the rows really change; the views reload only then, and scroll to
the top only when the listing is of a new folder. The model keeps the listing sorted
(`sortedSource`) until it or the sort changes, so Find only filters it. Selection syncs both
ways (`isUpdating` stops the loop). Column widths and order are saved by AppKit under the
autosave name `FileList`.

`DirectoryLoader` reads a folder with `contentsOfDirectory(at:includingPropertiesForKeys:)` in a
detached task, prefetching the values the columns need; it stops between items when its load is
cancelled, and asks for Finder's display name only when it's shown. Navigating clears the last
folder's items at once. `DirectoryWatcher` watches the folder's file descriptor for writes,
renames and deletes and reloads the listing after 150 ms of quiet (not a subfolder search). It
only sees entries added, removed or renamed, not edits inside files, and is kept until the
folder changes.

Icons: `IconCache.shared` holds per-type icons and up to 5000 per-item ones (folders, apps),
read in the background with a generic icon meanwhile. Desktop, Documents and Downloads
(`isGuardedFolder`) are asked nothing in Home beyond stat-level values. Reading their Finder tags
(an extended attribute on the folder itself) is what raised the access prompt just for listing
Home, found with a freshly signed probe app timing each lookup. Their kind, localized name, iCloud
state and icon (from CoreTypes.bundle) are skipped too, to be safe: after the first prompt is
answered, later lookups no longer prompt, so the probe couldn't clear them.
Listing iCloud Drive adds what Finder shows there (`ICloudDrive` in DirectoryLoader.swift): the
Desktop and Documents links (hidden on disk, treated as guarded folders) and the `Documents`
folder of each container in `~/Library/Mobile Documents` that iCloud doesn't mark hidden. The
sidebar tree and the breadcrumbs' › menus add the same (`ICloudDrive.sortedFolders`); breadcrumbs name them through
`Breadcrumbs.segments(iCloudHome:appName:)`. iCloud shows or hides a container with a flag on it,
which a folder watcher on the parent never sees, so iCloud Drive also runs an
`AppFoldersWatcher` (one FSEvents stream over Mobile Documents, only container-level changes).
The list's `FileTableView.draggingEnded` must not call super: NSTableView doesn't implement it,
and the exception broke drags. iCloud items opened, downloaded or evicted are polled by `BrowserModel.watchDownloads` (the
folder's watcher sees nothing) until they settle. The icon view's `ThumbnailCache` is an
`NSCache` limited by pixel bytes, and cancels a thumbnail when its item scrolls out of view. The
address bar's › menus list their folder only when clicked (an `NSMenu`; a SwiftUI `Menu` builds
its items with the view), and disk names come from `VolumeNames`, re-read on mount.

## Tests

`just test` runs Swift Testing suites for everything in `FileManagerCore`: keymap lookups and
conflicts, history, path resolution and completion, sorting, file operation planning, name
patterns and search filters, and batch rename previews and moves. Put new pure logic in
`FileManagerCore` and test it there; keep AppKit in the app target.

It also runs `FileManagerAppTests`, which test the app's models (`BrowserModel`,
`FileOperations`) through `@testable import FileManagerApp`. Each test makes a `Sandbox`: a
scratch folder in the temporary directory, a `BrowserServices` whose stores, session and
settings use their own UserDefaults suite and files in that folder, a private pasteboard, a
Trash inside the folder, and a `FakePresenter` that answers confirmations and counts beeps.
`FileOperations` reports errors to the sandbox instead of a modal alert, which would hang the
run. Nothing touches your folders, Trash or settings. Folder reads and file operations finish in the
background, so tests wait with `eventually { … }`.

### Snapshots

Debug builds have a hook (`DebugSnapshot.swift`) that draws the window into a PNG, prints the
whole menu bar with shortcuts and enabled state, and quits. It works without screen-recording
permission. The output ends with which view has the keyboard focus:

```bash
just snapshot                                    # build/snapshot.png of a demo folder
just snapshot "Backspace,Opt+Left,Cmd+H" out.png # press keys first, then capture
just snapshot "menu:New Folder,type:Reports,Return,Cmd+Z" out.png
```

Steps are key chords, `menu:<item title>`, `type:<text>`, `action:<Action raw value>` (runs it
on the window's model directly), `scope:subfolders` (Find's switch), `batch:<find>><replace>`
(a batch rename of the selection, as the sheet's Rename button runs it), `mouse:<x>/<y>` (a
click at window points from the top-left; the PNG is at 2x) and `click:list` (makes the file
list first responder through AppKit, as a click does, behind SwiftUI's back). When you're using
another app, macOS may not let File Manager become active; then nothing is key, Cmd shortcuts
don't reach the menu bar, and the hook falls back to the first window, so use `action:` steps.
The output lists the items shown and selected at the end.

Snapshot runs stay inside the demo folder so a fresh build never triggers macOS's folder-access
prompts: the window starts there instead of Home, the sidebar's folder tree is rooted there,
Locations lists no disks, and your saved session, recent folders, folder views and shortcuts
file are neither read nor written. To try opening folders from outside (`open -a`), send them
only while a snapshot instance is running; otherwise `open` starts a normal copy of the app. Keys go through the normal event
queue, so they exercise `KeyMonitor` and the menu bar like real key presses. Shifted Cmd
shortcuts (Shift+Cmd+N) don't match menus when synthesized; use `menu:` for those. The demo
folder (`build/snapshot-demo`) is recreated each run, and the hook refuses to press anything
once the window has left it, so a test can't touch real files. Undoing a copy or a new folder
moves it to the real Trash. The app is launched with `open`, so it becomes the active app; Cmd shortcuts only
reach the menu bar of the active app.

### The README picture

`just screenshot` makes a sample home folder (`build/screenshot/alex`, with Documents full of
made-up files), opens it in dark mode at 1100×620 and leaves the window up. The sidebar and
address bar show the sample folder as Home, so none of your own folders or names appear. Take
the picture yourself (Shift+Cmd+4, Space, then Opt-click the window to leave out its shadow),
quit the app, and run `just screenshot-save <file.png>` to write `docs/images/window.webp`. The
snapshot hook can't draw it: the sidebar's Liquid Glass rows come out dim or black in an
image drawn by the app.

## App icon

The icon is drawn by hand in `assets/icon.svg`: a white standing set of drawers on a blue
gradient tile, on Apple's 1024 icon grid (an 824-unit tile at 100,100 with a transparent
margin). The gaps and handles use the tile's gradient so they read as cut out of the cabinet.

After editing the SVG, run `just icons` (needs Inkscape: `brew install --cask inkscape`). It
regenerates `Resources/AppIcon.icns` and `assets/icon/icon.png` (the README's icon), which
are committed so builds don't need Inkscape.

## Signing

`scripts/bundle.sh` signs with the first Apple Development or Developer ID identity in your
keychain, or ad hoc (`-`) if there isn't one. Override with `SIGN_IDENTITY="…" just install`.
`just install` waits for the running copy to quit, then updates `~/Applications/File Manager.app`
in place with `rsync -a --delete` and re-registers it with LaunchServices. Deleting it and copying
a new one left a Dock pin pointing at the deleted app, since the Dock follows the app folder
itself, not just its path. rsync writes each changed file anew, which matters for the
executable: the kernel caches code signatures per file, so overwriting one in place gets it killed.
With ad-hoc signing, macOS may treat each rebuild as a new app and ask for folder access again.

## Continuous integration and releases

`.github/workflows/ci.yml` builds and runs the tests on every push to `main` and every pull
request, on GitHub's `xcode-27` runner (macOS 27 with Xcode 27; the app needs the macOS 27
SDK).

To release, bump `CFBundleShortVersionString` in `Resources/Info.plist`, commit, and push a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/release.yml` runs the tests, builds the app with the tag as its version
(`APP_VERSION`, without the `v`), zips it as `File-Manager-<version>.zip` and publishes a
GitHub release with it and generated notes. A tag with a hyphen (`v1.1.0-beta.1`) makes a
pre-release. The build is Apple Silicon only (macOS 27 doesn't run on Intel) and signed ad
hoc, not notarized, so the first launch needs **Open Anyway** (see
[Installing](Installing.md#the-first-time-you-open-it)). `just dist` makes the same zip
locally.
