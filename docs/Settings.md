# Settings

Open settings with **File Manager → Settings…** or **Cmd+,**. Changes apply straight away to
every window. Press **Esc** to close it.

## Files

**Show folders before files** (on by default) keeps folders at the top of the list whichever
column you sort by, as Explorer and the Linux file managers do. Turn it off to mix folders in
with files, as Finder does by default.

**Show all file extensions** (on by default) shows every name in full, `notes.txt` rather than
`notes`, as most Explorer and Linux users set it. Apps still show without `.app`. Turn it off to
follow Finder's choice (Finder → Settings → Advanced) and each file's own *Hide extension*
setting. Renaming always edits the full name, extension included, so you can add or remove an
extension even while it's hidden.

**Open items with a single click** (off by default) opens files and folders with one click, like
Explorer's single-click option or KDE's default. Shift-click and Cmd-click still select. With it
on, double-click isn't needed.

**Ask before moving items to the Trash** (off by default) asks before Delete or Cmd+Backspace
trashes anything. Off, trashing happens straight away; Cmd+Z puts it back.

## Windows

**Reopen windows and tabs from last time** (on by default) brings back your windows and tabs,
each in the folder it was showing, when File Manager starts. Turn it off to start with one
window on the start folder. See [Tabs and windows](Tabs-and-Windows.md#reopening-where-you-left-off).

**New windows open** picks that start folder: Home (the default), Desktop, Documents, Downloads,
or any folder you choose with **Other Folder…**. If that folder isn't there (on a disk that's
unplugged), Home is used. New windows and tabs opened from a window (Cmd+N, Cmd+T) show the same
folder as the window you're in, as in Explorer.

## Path Bar

**Shorten home path in breadcrumbs** (on by default) shows your home folder as one **~** folder
in the address bar, so `Macintosh HD › Users › you › Documents` reads `~ › Documents`. Click
**~** to go home. Folders outside your home folder show their full path either way. See
[The address bar](Using-the-App.md#the-address-bar).

## Keyboard

**Edit Shortcuts File…** opens your shortcuts file (making a starter one the first time) and
**Reload** reads it again. Problems with the file are listed here. See
[Custom shortcuts](Custom-Shortcuts.md).

## Open Terminal Here

**Terminal app** picks what F4 and Go → Open Terminal Here open:

| Choice | Opens |
|---|---|
| Terminal | macOS Terminal (the default) |
| iTerm | iTerm2 |
| Ghostty | Ghostty |
| Other App… | any app you choose; it's given the folder to open |

Apps that aren't installed are marked *(not installed)*. If the chosen app can't be found when
you press F4, File Manager tells you and points you back here.

With **Other App…**, File Manager opens the folder with that app the same way as dragging the
folder onto its Dock icon. Most terminal apps (and editors such as VS Code) open a window in
that folder.

---
Next: [Troubleshooting](Troubleshooting.md)
