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
- Folders are listed before files, and names with numbers sort by value (`file2` before
  `file10`).

## What's different

### Cmd instead of Ctrl

Shortcuts that use **Ctrl** on Windows and Linux use **Cmd** here: Cmd+L, Cmd+A, Cmd+N. That's
where every other Mac app expects them, and Ctrl+arrow keys belong to macOS (switching Spaces).
**Alt** shortcuts use **Opt**, the key in the same place.

### Return renames, it doesn't open

On a Mac, Return renames the selected file, and File Manager keeps that. To open, use **Cmd+O**,
**Cmd+Down** or **Cmd+Return**, or double-click. (Renaming arrives with file operations; until
then Return does nothing in the list.)

### Cmd+H shows hidden files instead of hiding the app

On a Mac, Cmd+H normally hides the app. Here it toggles hidden files, like Ctrl+H on Linux.
**Hide File Manager** is still in the File Manager menu without a shortcut, and **Opt+Cmd+H**
still hides other apps. Cmd+Shift+. (Finder's shortcut for hidden files) works too.

### F4 opens your terminal app, not a panel

Dolphin's F4 opens a terminal panel inside the window. Here F4 opens the current folder in a
separate terminal app: Terminal, iTerm, Ghostty or another app you choose in
[Settings](Settings.md).

### No Alt+Home

Home is **Shift+Cmd+H**, as in Finder. Shift+Cmd+D, Shift+Cmd+O, Opt+Cmd+L and Shift+Cmd+A go to
Desktop, Documents, Downloads and Applications.

### Function keys on a MacBook

On a MacBook, the top row controls brightness and volume by default, so F4, F5 and F6 need the
**fn** key held down. To use them without fn, turn on System Settings → Keyboard →
Keyboard Shortcuts → Function Keys → *Use F1, F2, etc. keys as standard function keys*. Every
F-key action also has a Cmd shortcut.

---
Next: [Settings](Settings.md)
