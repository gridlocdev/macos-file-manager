# Copying and moving files

Copy, cut and paste work the way they do in Explorer and the Linux file managers, including
**cut and paste to move**, which Finder doesn't have. Everything you do here can be undone with
**Cmd+Z**, except Delete Immediately.

## Copy, cut and paste

| To | Do this |
|---|---|
| Copy items | select them, **Cmd+C**, go to the folder, **Cmd+V** |
| Move items | select them, **Cmd+X**, go to the folder, **Cmd+V** |
| Duplicate items in the same folder | **Cmd+D**, or Cmd+C then Cmd+V in the same folder |
| Copy the full path of items | **Shift+Cmd+C** (or Opt+Cmd+C); with nothing selected, the folder's path |

- Items you've cut are **dimmed** until you paste them. Copying something else cancels the cut,
  and the items stay where they were.
- After a cut is pasted, the clipboard is emptied, so pasting again doesn't try to move the
  same items twice.
- Pasted items are selected afterwards, so you can see what arrived.
- Duplicates are named like Explorer's: `notes - Copy.txt`, then `notes - Copy (2).txt`.
- Paths are copied one per line, without quotes.

### With Finder and other apps

The clipboard is the normal macOS one, so:

- Files copied in File Manager paste into Finder, and the other way round.
- Files copied in Finder can be **moved** here with **Move Items Here** (Opt+Cmd+V), the same
  shortcut Finder uses.
- A cut in File Manager is only a cut inside File Manager. If you paste into Finder, Finder
  copies.

## When names clash

If an item with the same name is already in the folder, File Manager asks what to do:

| Choice | What happens |
|---|---|
| **Replace** | The existing item goes to the **Trash** (not deleted), and the new one takes its place. |
| **Keep Both** | The new one gets a number: `notes (2).txt`. |
| **Skip** | That item isn't copied or moved. |
| **Stop** | Nothing more happens. Anything already done stays done. |

When several items clash, tick **Do this for the next … conflicts** to answer once for all of
them.

### Folders merge

Copying or moving a folder onto a folder with the same name **merges** them, like Explorer and
Linux: everything inside is added to the existing folder, and you're only asked about files that
clash. Finder does it differently: it replaces the whole folder. After a merged move, the
original folder is removed if it ended up empty.

You can't copy or move a folder into itself or into one of its own subfolders.

## New folders and files

- **New Folder** (Shift+Cmd+N) makes `New Folder` (or `New Folder (2)`…) and starts renaming
  it straight away. Type the name and press Return.
- **New Text File** (Opt+Cmd+N) does the same with an empty `New Text File.txt`.

## Renaming

Press **Return** or **F2** with an item selected. The name is selected without its extension,
so typing replaces `notes` and keeps `.txt`. Press **Return** (or click elsewhere) to save, or
**Esc** to cancel. You can change only the capitalisation (`notes` to `Notes`) too.

Names can't be empty, contain `/` or `:`, or be the same as another item in the folder.

## Trash and deleting

- **Move to Trash**: **Cmd+Backspace**, or **Delete** (forward delete, fn+delete on a MacBook).
  The next item down is selected, so you can keep pressing it.
- **Delete Immediately…**: **Opt+Cmd+Backspace** or **Shift+Delete**. It asks first, skips the
  Trash, and **can't be undone**.

Return and Delete only work on files while the file list has the keyboard focus, so pressing
them in the sidebar does nothing to your files.

### The Trash and Put Back

**Go → Trash** shows the Trash. macOS only lets apps see inside it with **Full Disk Access**
(System Settings → Privacy & Security → Full Disk Access); without it, File Manager says so.

**File → Put Back** moves the selected items back to where they came from, recreating the folder
if it's gone. It only works for items **File Manager** moved to the Trash: it keeps a note of
where each one came from. For items trashed in Finder or another app, use Put Back in Finder.

Emptying the Trash is left to Finder.

## Undo and redo

**Cmd+Z** undoes the last change and **Shift+Cmd+Z** redoes it. There's one history for the
whole app, like Explorer's, so Cmd+Z in any window undoes the most recent change wherever it
was.

| You did | Undo does |
|---|---|
| Copy or duplicate | moves the copies to the Trash |
| Move or rename | moves or renames them back |
| New folder or file | moves it to the Trash |
| Move to Trash | puts it back where it was |
| Replace (in a clash) | puts the replaced item back from the Trash |
| Delete Immediately | nothing: it can't be undone |

While you're typing in the address bar or renaming, Cmd+Z undoes typing instead.

## Progress and cancelling

Copies and moves run in the background. If one takes more than a moment, the
**File Operations** window opens with a progress bar for each, and closes when they're done.
Click **✕** to stop one. Whatever was already copied or moved stays, and **Cmd+Z** undoes it.

A single large file is copied in one go, so Cancel takes effect after it.

---
Next: [Drag and drop](Drag-and-Drop.md)
