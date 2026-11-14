# File Manager documentation

File Manager is a file browser for macOS that works the way Windows Explorer and Linux file managers (Nautilus, Dolphin) do. These pages cover how to use it, where it differs from what you're used to, and how to work on its code.

## Using File Manager

- [Getting started](getting-started.md): what you need, downloading and opening it the first time, building it yourself, permission prompts, updating and uninstalling.
- [Features](features.md): the parts of the window, typing a path, the right-click menu, Quick Look, Get Info and the status bar.
- [Copying and moving files](copying-and-moving-files.md): cut and paste, what happens when names clash, folders that merge, undo, and Put Back.
- [Drag and drop](drag-and-drop.md): when a drag moves and when it copies, and dropping on the sidebar.
- [Views and columns](views-and-columns.md): thumbnails, extra columns such as Date Created, grouping by date, and the preview pane.
- [Searching and selecting](searching-and-selecting.md): finding a file in subfolders, filtering by kind or date, and selecting every `.jpg`.
- [Batch rename](batch-rename.md): renaming many files at once, numbering them, and undoing it.
- [Tabs and windows](tabs-and-windows.md): opening a folder in a new tab, seeing two folders side by side, and getting your tabs back after quitting.
- [The sidebar](sidebar.md): pinning a folder, Recent, and ejecting a drive.
- [Controls](controls.md): every shortcut, with what you'd press in Windows or Linux.
- [Coming from Windows and Linux](coming-from-windows-and-linux.md): why it uses Cmd and not Ctrl, why Return renames, and which key deletes.
- [Using with Finder](using-with-finder.md): opening a folder from Finder in File Manager, and what always opens in Finder.
- [iCloud and tags](icloud-and-tags.md): files that are only in iCloud, tagging files and finding tagged ones, and zipping and unzipping.
- [Custom shortcuts](custom-shortcuts.md): changing a shortcut, or giving a command like Compress one.
- [Settings](settings.md): picking your terminal app, mixing folders in with files, and the other options.
- [Troubleshooting](troubleshooting.md): permission prompts, folders that won't open, and other things that don't behave as expected.

Some questions these pages answer:

- [Why does Return rename instead of open?](coming-from-windows-and-linux.md#return-renames-it-doesnt-open)
- [What happens when I paste a folder onto one with the same name?](copying-and-moving-files.md#folders-merge)
- [How do I see two folders side by side?](tabs-and-windows.md#split-view)
- [A folder says "Can't Open Folder"](troubleshooting.md)

## Working on File Manager

- [Development](development.md): setting up, VS Code, every just recipe, tests and snapshots, the screenshot, the app icon, signing, and releases.
- [Architecture](architecture.md): the code layout, how a shortcut runs, file operations and undo, drag and drop, windows and tabs, the sidebar and the file list.
