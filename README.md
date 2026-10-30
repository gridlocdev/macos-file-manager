# File Manager

Manage your files on a Mac the way you would on Windows or Linux.

Finder has its own patterns for moving around and working with files, and they take some
getting used to. If you also use Windows Explorer or a Linux file manager like Nautilus or
Dolphin, switching between the two means changing your muscle memory every time, which is a
real challenge. File Manager brings those familiar patterns to the Mac, with the same keys and
the same behaviour. It uses Cmd where Windows and Linux use Ctrl, and keeps the Mac conventions
worth keeping. [Coming from Windows and Linux](docs/Coming-from-Windows-and-Linux.md) lists
what carries over and what's different.

![File Manager in dark mode: a sidebar with pinned folders and a folder tree, back, forward and up buttons, an address bar reading ~ › Documents, and a details list of folders and files with their dates and kinds](docs/images/window.webp)

## What it does

- **Explorer and Linux shortcuts**: Backspace for up, F2 to rename, F5 to refresh, Cmd+L to
  type a path (Tab completes it), Cmd+H for hidden files and F4 for a terminal here.
- **Cut, copy and paste files**, with folders that merge, a choice of Replace, Keep Both or
  Skip when names clash, and one undo for everything.
- **Tabs and split view**: open folders in tabs, or two side by side (F3) to copy between
  them. Your windows and tabs come back next time.
- **A sidebar** with pinned and recent folders, drives you can eject, and a folder tree.
- **Details or icons**, with thumbnails, a preview pane, extra columns and grouping, remembered
  for each folder.
- **Find as you type** in a folder or all its subfolders, with filters by kind, date and size.
- **Batch rename** with find and replace, numbering and a live preview.
- **Drag and drop** that moves on the same disk and copies to another, like Finder.
- **Works alongside Finder**: tags, iCloud downloads, Quick Look, Open With, Share and zip.
- **Your own shortcuts** for any command, in a small settings file.

## Download

Get the latest version from the [Releases](../../releases) page. It needs macOS 27 or later on
a Mac with Apple Silicon. The first time you open it, macOS asks you to confirm; the
[installing guide](docs/Installing.md) shows how.

## Documentation

**[Read the documentation](docs/Home.md)** for how to use the app, for example:

- [What are all the keyboard shortcuts?](docs/Keyboard-Shortcuts.md)
- [Why does Return rename instead of open?](docs/Coming-from-Windows-and-Linux.md#return-renames-it-doesnt-open)
- [What happens when I paste a folder onto one with the same name?](docs/Copying-and-Moving-Files.md#folders-merge)
- [How do I see two folders side by side?](docs/Tabs-and-Windows.md#split-view)
- [A folder says "Can't Open Folder"](docs/Troubleshooting.md)

## For developers

Building, testing, the code layout and releases are covered in the
[developer guide](docs/Developer-Guide.md).

## License

[MIT](LICENSE)
