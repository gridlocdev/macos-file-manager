# Using the app

Each File Manager window shows one folder. Open more windows with **Cmd+N**.

![File Manager window with hidden files shown](images/window.webp)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ ‹  ›  ↑   Documents   [ ~/Documents                                   ] │ ← toolbar
├──────────────┬──────────────────────────────────────────────────────────┤
│ Favorites    │ Name                 Date Modified       Kind      Size   │
│  ⌂ Home      │ 📁 Projects          Oct 2, 2026 9:14    Folder      --   │
│  ▭ Desktop   │ 📁 Receipts          Sep 30, 2026 18:02  Folder      --   │
│  ▤ Documents │ 📄 notes.txt         Oct 28, 2026 22:40  Plain Text  2 KB │
│  ↓ Downloads │                                                          │
│  ⊞ Apps      │                                                          │
│ Locations    │                                                          │
│  ▣ Macintosh │                                                          │
│              ├──────────────────────────────────────────────────────────┤
│              │ 3 items, 1 selected                                      │ ← status bar
└──────────────┴──────────────────────────────────────────────────────────┘
```

## The toolbar

- **‹ ›** go back and forward through the folders you've visited in this window
  (Opt+Left / Opt+Right, Cmd+[ / Cmd+], or the back and forward buttons on your mouse).
- **↑** goes to the enclosing folder (Backspace, Opt+Up or Cmd+Up). The folder you came from is
  selected, so you can go straight back down with Cmd+Down.
- **The address bar** shows where you are. `~` means your home folder.

## Typing a path

Press **Cmd+L** (or Opt+D, as on Windows) to jump to the address bar, then type and press
**Return**. You can type:

| You type | Goes to |
|---|---|
| `/Applications` | that exact folder |
| `~/Downloads` | Downloads in your home folder |
| `Projects` | a folder inside the current one |
| `..` | the enclosing folder |
| `~/Documents/notes.txt` | the Documents folder, with `notes.txt` selected |

**Tab** completes folder names as you type: `~/Doc` then Tab becomes `~/Documents/`. If several
folders match, Tab fills in as much as they have in common. Names are matched regardless of
case, and hidden folders are only suggested once you type the leading `.`.

**Esc** puts the address back as it was and returns to the file list.

## The sidebar

**Favorites** has your home folder, Desktop, Documents, Downloads, Applications and iCloud Drive.
**Locations** lists your Mac's disk and any mounted drives, disk images or network shares; it
updates when you connect or eject one. Click an item to open it.

## The file list

- **Open** a folder or file by double-clicking it, or select it and press Cmd+O, Cmd+Down or
  Cmd+Return. Folders open in the same window; files open in their default app. Return doesn't
  open: it renames, as in Finder.
- **Select** with the arrow keys, Shift for a range, Cmd+click to add or remove one item, and
  Cmd+A for everything.
- **Type a name** to jump to it: typing `rec` selects the first item starting with "rec".
- **Sort** by clicking a column heading; click again to reverse. View → Sort By does the same.
  Folders stay at the top unless you turn that off in [Settings](Settings.md).
- **Resize and reorder** columns by dragging their edges and headings. The layout is remembered.

Hidden files (names starting with `.`, and files marked hidden) are off by default. **Cmd+H** or
**Cmd+Shift+.** (View → Show Hidden Files) shows them, dimmed; press again to hide them. The
status bar says when they're shown.

The list updates by itself when files are added, removed or renamed in the folder. **F5** or
**Cmd+R** refreshes it by hand.

## Working with files

The File and Edit menus have everything for changing files: **New Folder**, **New Text File**,
**Rename** (Return or F2), **Duplicate**, **Cut**, **Copy**, **Paste**, **Copy Path**,
**Move to Trash** (Cmd+Backspace or Delete), **Delete Immediately…** and **Put Back**, and
**Undo** for all of them. [Copying and moving files](Copying-and-Moving-Files.md) explains each
one, what happens when names clash, and how folders merge.

## The right-click menu

Right-click an item (or press **Shift+F10**, as in Windows) for a menu of what you can do with
it. If it isn't already selected, it's selected first.

| On an item | |
|---|---|
| **Open**, **Open With** | Open With lists every app that can open the item, the default first, and **Other…** for any app. |
| **Quick Look** | A preview, as with Space. |
| **Cut**, **Copy**, **Duplicate**, **Rename** | As in the Edit and File menus. |
| **Copy Path**, **Get Info** | |
| **Open Terminal Here** | For a folder: a terminal in that folder. |
| **Show in Finder** | Opens the item in Finder, selected. |
| **Move to Trash** (or **Put Back** in the Trash) | |
| **Share** | AirDrop, Mail, Messages and the other share options. |
| **Services** | What other apps add for files, if any. |

Right-clicking empty space in the list deselects everything and shows a menu for the folder
itself: **New Folder**, **New Text File**, **Paste**, **Sort By**, **Show Hidden Files**,
**Refresh**, **Open Terminal Here**, **Copy Path**, **Get Info** and **Show in Finder**.

## Quick Look

Press **Space** to preview the selected items without opening them: pictures, PDFs, videos,
text, documents and more. Press Space again (or Esc) to close it. With the preview open, the
arrow keys move through the list and the preview follows.

## Get Info

**Cmd+I** or **Opt+Return** (Alt+Enter in Windows) opens an Info window for the selection,
like Explorer's Properties. With nothing selected, it shows the folder you're in.

- **One item**: size (folders are added up in the background, with how many items and how
  much space they take on disk), where it is, when it was created, modified and last opened,
  which app opens it, and its permissions for you, the group and everyone (with the Unix mode
  as `drwxr-xr-x` / `755`).
- **Several items**: how many, and their total size.

The window stays open while you work, so you can open several. Close it with Cmd+W.

## The status bar

The bar under the list shows how many items there are, how many are selected and the total size
of the selected files, and how much space is free on the disk:
*12 items, 3 selected (4.2 MB), 120 GB available*. As in Explorer, selected folders aren't added
up there; use Get Info for that.

## Moving around with the keyboard

**F6** moves the keyboard focus between the sidebar, the address bar and the file list, like F6
in Explorer; **Shift+F6** goes the other way. Tab works too, as in any Mac window.

## Open Terminal Here

**F4** or **Cmd+Opt+T** (Go → Open Terminal Here) opens the current folder in your terminal app.
It's Terminal unless you pick another one in [Settings](Settings.md).

---
Next: [Copying and moving files](Copying-and-Moving-Files.md)
