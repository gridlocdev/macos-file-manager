# Coming from Windows and Linux

File Manager keeps the shortcuts and behaviour of Windows Explorer and the Linux file managers
(Nautilus, Dolphin), but runs on a Mac keyboard. This page lists what carries over and what's
different, and why.

## What works the same

- **Backspace** goes up a folder (older Explorer, Nautilus, Dolphin). **Alt+Up** (here Opt+Up)
  does too.
- **Alt+Left / Alt+Right** (here Opt+Left / Opt+Right) go back and forward, and so do the side
  buttons on your mouse.
- **Alt+D** (here Opt+D) and **Ctrl+L** (here Cmd+L) jump to the address bar, and you can type or
  paste a path into it. Tab completes folder names, as in a Linux location bar.
- **F5** refreshes.
- **F6** moves between the sidebar, the address bar and the file list.
- **F4** opens a terminal in the current folder, like Dolphin.
- **Ctrl+H** shows hidden files (here Cmd+H), as in Nautilus and Dolphin.
- Going up a folder selects the folder you came from, as Explorer does.
- **Cut and paste moves files** (Cmd+X, Cmd+V). Finder can't do that.
- Pasting a folder onto one with the same name **merges** them, and clashing files offer
  Replace, Keep Both or Skip. Finder would replace the whole folder.
- **F2** renames, **Ctrl+Shift+N** (here Shift+Cmd+N) makes a new folder, duplicates are named
  `name - Copy`, and **Shift+Delete** deletes without the Trash (after asking).
- One undo history for the whole app, like Explorer's: Cmd+Z undoes copies, moves, renames,
  new folders and trashing.
- **Tabs** like Explorer's and Nautilus's: Cmd+T, Ctrl+Tab, middle-click a folder to open it
  in a new tab, Shift+Cmd+T to reopen a closed one. Cmd+1…9 jump to a tab (Alt+1…9 in
  Nautilus).
- The **address bar** shows clickable folders with › menus of subfolders, like Explorer's.
- The **sidebar** has pinned folders (Quick access), recent folders and a folder tree that
  follows where you are (the navigation pane).
- **Shift+F10** opens the right-click menu, and **Alt+Enter** (here Opt+Return) opens an item's
  properties (Get Info).
- Dragging moves on the same disk and copies to another disk, as in Explorer. To force it,
  hold **Opt** to copy or **Cmd** to move (Explorer uses Ctrl and Shift).
- Folders are listed before files, and names with numbers sort by value (`file2` before
  `file10`).

## What's different

### Cmd instead of Ctrl

Shortcuts that use **Ctrl** on Windows and Linux use **Cmd** here: Cmd+L, Cmd+A, Cmd+N. That's
where every other Mac app expects them, and Ctrl+arrow keys belong to macOS (switching Spaces).
**Alt** shortcuts use **Opt**, the key in the same place.

### Return renames, it doesn't open

On a Mac, Return renames the selected file, and File Manager keeps that (F2 works too). To open,
use **Cmd+O**, **Cmd+Down** or **Cmd+Return**, or double-click.

### Which key deletes

Mac keyboards label Backspace as *delete* (⌫). Here, as in Explorer and Linux, **Backspace goes
up a folder**, so it can't also be the delete key. To move items to the Trash, press
**Cmd+Backspace** (the Finder shortcut) or **forward Delete** (⌦; **fn+delete** on a MacBook),
which is where Delete sits on a PC keyboard. **Shift+Delete** deletes immediately, after asking.

### Put Back only for items File Manager trashed

Explorer's Recycle Bin can restore anything. macOS keeps that information private to Finder, so
File Manager can only put back items it moved to the Trash itself. See
[Copying and moving files](Copying-and-Moving-Files.md#the-trash-and-put-back).

### Cmd+H shows hidden files instead of hiding the app

On a Mac, Cmd+H normally hides the app. Here it toggles hidden files, like Ctrl+H on Linux.
**Hide File Manager** is still in the File Manager menu without a shortcut, and **Opt+Cmd+H**
still hides other apps. Cmd+Shift+. (Finder's shortcut for hidden files) works too.

### F4 opens your terminal app, not a panel

Dolphin's F4 opens a terminal panel inside the window. Here F4 opens the current folder in a
separate terminal app: Terminal, iTerm, Ghostty or another app you choose in
[Settings](Settings.md).

### Find is Cmd+F, not F3

In Explorer, F3 and Ctrl+E also start a search. Here search is **Cmd+F** only, and it filters
the list as you type rather than opening a results page. F3 is kept for a split view, as in
Dolphin (planned). Cmd+S selects by pattern, like Ctrl+S in Nautilus, since there's nothing to
save. See [Searching and selecting](Searching-and-Selecting.md).

### No Alt+Home

Home is **Shift+Cmd+H**, as in Finder. Shift+Cmd+D, Shift+Cmd+O, Opt+Cmd+L and Shift+Cmd+A go to
Desktop, Documents, Downloads and Applications.

### Function keys on a MacBook

On a MacBook, the top row controls brightness and volume by default, so F4, F5 and F6 need the
**fn** key held down. To use them without fn, turn on System Settings → Keyboard →
Keyboard Shortcuts → Function Keys → *Use F1, F2, etc. keys as standard function keys*. Every
F-key action also has a Cmd shortcut.

---
Next: [Using with Finder](Using-with-Finder.md)
