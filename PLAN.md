# macos-file-manager plan

macOS file manager. Explorer/Linux behavior, Cmd as modifier, macOS ergonomics kept (Return = rename).

## Stack
- SwiftPM executable, no Xcode project. Swift 6 strict concurrency, macOS 27+ (all the user's Macs). Liquid Glass and current SwiftUI APIs used without `#available` checks.
- SwiftUI shell; AppKit `NSTableView` (via `NSViewRepresentable`) for details view, `NSCollectionView` for icon view. SwiftUI `Table` swallows keys, weak type-ahead, slow on big dirs.
- `justfile`: `build`, `run`, `run-attached`, `test`, `bundle`, `install` (~/Applications), `fmt`. Always `xcrun swift …`.
- VS Code: Swift extension (swiftlang), `.vscode/launch.json` (lldb-dap), `tasks.json` → just recipes.
- Not sandboxed (personal tool). Full Disk Access optional.
- No third-party deps; ask before adding any.

## Architecture
Foundations everything else builds on (all in M1–M2):
- `AppModel` `@MainActor @Observable`: windows, tabs, clipboard state, settings.
- `BrowserModel` (one per tab): current URL, back/forward history, selection, sort, view mode, show-hidden. Tabs (M4) and split view (M8) are just more of these.
- `DirectoryLoader`: async listing (resource keys prefetched), FSEvents watcher → refresh.
- `Keymap`: one table action → shortcut(s). Menu bar runs each item's shown Cmd chord; a per-window `NSEvent` monitor runs the rest (skipped while a text field edits). Right-click menu (M3) and docs test also read it. Menu bar finds the key window via `ActiveBrowser` (not `@FocusedValue`); menu items stay enabled, `perform` beeps.
- `Actions`: every user command (open, rename, trash, copy path…) defined once with "enabled for selection" rule; menus, context menu, keys, toolbar call it.
- `FileOps` (M2): queued jobs in `Task.detached` w/ progress + cancel; conflicts; undo log. Clipboard, drag and drop, Put Back, batch rename, compress all go through it.
- `SizeCalculator` (M3): async folder sizes, cached; used by Get Info, status bar, size column.
- `Settings`: `@AppStorage`-backed; each setting lands with its feature.
- Pure logic testable w/o I/O: keymap, history, path parsing/autocomplete, conflict naming, folder-merge planning, sort/group, pattern match, batch-rename preview.

## Milestones
Status: M1–M7 done (2026-10-29). Not done from M4: dropping files onto a tab.

Ordered by how essential to everyday file management, then by what later features need.

1. **Foundation + browsing** (everything depends on it)
   - Local `git init`, package, justfile, VS Code config, `.app` bundle w/ Info.plist ("File Manager"), `install` recipe, app icon via `/app-icon` (standing set of drawers).
   - `Keymap` + `Actions` + full menu bar built from them; Settings window (terminal choice, folders first).
   - Window: sidebar (favorites, home, volumes), text address bar (Tab autocomplete), details list (Name / Date modified / Kind / Size, sortable, resizable), status bar (item count, selected count).
   - Navigation: open, up (reselects folder you came from), back/forward, refresh, hidden files toggle, mouse back/forward buttons.
   - Keyboard: type-ahead select, F6/Tab focus cycle (sidebar → address bar → list).
   - Open Terminal Here (F4) using the terminal setting.
2. **File operations** (needed by M3 drag/drop, Put Back, batch rename, compress)
   - `FileOps` queue: progress window, cancel, several jobs at once.
   - Conflicts: Replace / Skip / Keep both (`name (2)`), folders merge like Explorer/Linux (not Finder's replace), "apply to all".
   - Undo/redo for copy, move, rename, new, trash.
   - Rename (selects name w/o extension), new folder, new text file, duplicate, trash, delete forever (confirm).
   - Clipboard cut/copy/paste w/ Finder interop, cut items dimmed; copy path.
   - Trash: browse it in-app, Put Back for items this app trashed (logged). Items trashed elsewhere: no Put Back.
3. **Direct manipulation + inspect**
   - Drag and drop: within app, to/from Finder and other apps, spring-loaded folders, Opt = copy / Cmd = move, default by volume.
   - Right-click menu (+ Shift+F10): Open, Open With, Rename, Duplicate, Trash, Copy, Cut, Paste, Copy Path, Get Info, Open Terminal Here, Show in Finder, Services, Share.
   - Get Info panel: size (folder sizes async), dates, kind, permissions, default app.
   - Quick Look (Space).
   - Status bar: selection size, free space on volume.
4. **Navigation + tabs**
   - Address bar breadcrumbs (click segment; dropdown of subfolders; click blank area = edit text).
   - Sidebar folder tree (expands to current folder), pin folders by drag, Recent folders, eject volumes.
   - Tabs: new/close, Ctrl+Tab, Cmd+1…9, middle-click folder → new tab, drag files onto tab, drag tab out → new window, reopen closed tab.
   - Session restore: windows + tabs + folders at launch.
5. **Find + select**
   - Cmd+F filter in current folder; toggle to search subfolders w/ filters (kind, date, size), Spotlight (`NSMetadataQuery`) + walk fallback.
   - Selection: invert, select by pattern.
   - Batch rename (multi-select + rename): find/replace, numbering, case, live preview (reuses pattern match + FileOps).
6. **Views + preview**
   - Icon grid view w/ thumbnails (`QLThumbnailGenerator`), zoom (Cmd+= / Cmd+- / Cmd+scroll).
   - Column chooser (right-click header: created, extension, permissions…), Group by (kind, date, size).
   - Per-folder view memory (stored in app support, never written into folders).
   - Docked preview pane (Opt+P).
   - Settings: show extensions, single-click open, confirm before trash, start folder.
7. **macOS integration + power settings**
   - Register as folder handler + "Open in File Manager" Service; docs explain what still goes to Finder.
   - Compress / extract zip (via `ditto`, through FileOps).
   - iCloud status badge; download / remove download.
   - Finder tags: show, assign, filter.
   - Remappable keymap file (JSON overrides on top of defaults).
8. **Extras**
   - Split view (two `BrowserModel`s side by side, F3).
   - Connect to Server (SMB/SFTP via NetFS).
   - Release build polish.

## Keybindings
| Action | Keys | M |
|---|---|---|
| Open | Cmd+Down, Cmd+O, Cmd+Return, double-click | 1 |
| Up | Backspace, Opt+Up, Cmd+Up | 1 |
| Back / Forward | Opt+Left/Right, Cmd+[ / ], mouse buttons 4/5 | 1 |
| Address bar | Cmd+L, Opt+D | 1 |
| Refresh | F5, Cmd+R | 1 |
| Hidden files | Cmd+H, Cmd+Shift+. | 1 |
| Select all | Cmd+A | 1 |
| Focus next/prev area | F6 / Shift+F6, Tab / Shift+Tab | 1 |
| Go to Home/Desktop/Documents/Downloads/Applications | Cmd+Shift+H / D / O, Opt+Cmd+L, Cmd+Shift+A | 1 |
| Terminal here | F4, Cmd+Opt+T | 1 |
| New window | Cmd+N | 1 |
| Type-ahead select | typing letters in list | 1 |
| Copy / Cut / Paste | Cmd+C / Cmd+X / Cmd+V | 2 |
| Undo / Redo | Cmd+Z / Cmd+Shift+Z | 2 |
| Rename | Return, F2 | 2 |
| New folder / new text file | Cmd+Shift+N / Cmd+Opt+N | 2 |
| Duplicate | Cmd+D | 2 |
| Trash / delete forever | Cmd+Backspace, fwd Delete / Shift+fwd Delete (confirm) | 2 |
| Copy path | Cmd+Shift+C | 2 |
| Context menu | Shift+F10, right-click | 3 |
| Get Info | Opt+Return, Cmd+I | 3 |
| Quick Look | Space | 3 |
| Tabs | Cmd+T, Cmd+W, Ctrl+Tab / Ctrl+Shift+Tab, Cmd+1…9 | 4 |
| Reopen closed tab | Cmd+Shift+T | 4 |
| Search / filter | Cmd+F | 5 |
| Invert selection / select by pattern | Cmd+Shift+I / Cmd+S | 5 |
| Icons / details view | Cmd+Shift+2 / Cmd+Shift+6 | 6 |
| Zoom in / out / reset | Cmd+= / Cmd+- / Cmd+0 | 6 |
| Preview pane | Opt+P | 6 |
| Split view | F3 | 8 |

## Menu bar ("File Manager")
- File Manager: About, Settings… (Cmd+,), Hide (no Cmd+H), Hide Others, Quit.
- File: New Window, New Tab, New Folder, New Text File, Open, Open With, Rename, Duplicate, Get Info, Compress, Move to Trash, Close Tab/Window.
- Edit: Undo/Redo, Cut/Copy/Paste (files or text), Copy Path, Select All, Invert Selection, Select by Pattern, Find.
- View: Details / Icons, Sort By, Group By, Columns, Show Hidden Files, Preview Pane, Zoom, Split View, Refresh.
- Go: Back, Forward, Enclosing Folder, Home/Desktop/Documents/Downloads/Applications, Recent Folders, Trash, Go to Location…, Open Terminal Here, Connect to Server.
- Window, Help: standard (Help opens docs).
Items appear as their milestone lands; shortcuts shown come from the keymap.

## Documentation (manual, like warmshift / exif-viewer)
- `docs/` wiki-style: `Home.md` + `_Sidebar.md`, flat hyphenated pages, relative `.md` links, images `docs/images/*.webp`, ASCII window sketches where useful. Plain language, user-first.
- README.md for users: screenshot, install, "Read the documentation" + question-style links into docs. Developer details only in Developer-Guide.
- Pages, by milestone:
  - M1: `Home`, `_Sidebar`, `Installing` (build/install, Gatekeeper w/ ad-hoc signing, Full Disk Access, permission prompts), `Using-the-App` (window tour), `Keyboard-Shortcuts` (grouped, Windows/Linux equivalent column), `Coming-from-Windows-and-Linux` (Cmd as modifier, Return renames, Cmd+H, F3 = split view not search, F4 opens your terminal app not a panel), `Settings`, `Troubleshooting`, `Developer-Guide` (recipes, VS Code, code layout, keymap/actions, adding a shortcut, tests).
  - M2: `Copying-and-Moving-Files` (clipboard, conflicts, folder merge vs Finder, undo, trash, Put Back only for items this app trashed).
  - M3: `Drag-and-Drop`, extend `Using-the-App` (right-click menu, Get Info, Quick Look).
  - M4: `Tabs-and-Windows`, `Sidebar` (tree, pins, recents, volumes).
  - M5: `Searching-and-Selecting`, `Batch-Rename`.
  - M6: `Views-and-Columns`.
  - M7: `Using-with-Finder` (what can't be replaced: desktop, Dock, "Show in Finder" elsewhere; folder handler, Service), `iCloud-and-Tags`, `Custom-Shortcuts`.
  - M8: extend pages for split view, servers.
- CLAUDE.md rule: update the page describing a behavior in the same commit that changes it.
- Test: every `Keymap` action appears in `Keyboard-Shortcuts.md` with matching keys, so the page can't drift.

## Decisions
- Open: Cmd+Down, Cmd+O, Cmd+Return, double-click.
- Hidden files: Cmd+H (replaces macOS Hide; Hide stays in app menu without shortcut) + Cmd+Shift+.
- Terminal for "open here": setting (Terminal, iTerm, Ghostty, custom app).
- macOS 27 minimum (`LSMinimumSystemVersion` 27.0, `platforms: [.macOS("27.0")]`).
- Name: repo `macos-file-manager`, app/menu bar name "File Manager" (`CFBundleName`, also embedded in the binary so `swift run` shows it).
- Local git only, no GitHub yet.
- Icon: standing set of drawers (app-icon skill).
- Single pane + tabs is the default; split view is an extra (M8).
- Views: Cmd+Shift+2 icons / Cmd+Shift+6 details (Cmd+1…9 = tabs).
- Search: Cmd+F only; F3 = split view (Dolphin).
- Put Back: only items this app trashed; no Finder hand-off.
- No embedded terminal; Open Terminal Here (configurable app) covers it.

## Unresolved questions
None.
