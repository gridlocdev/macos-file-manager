# Views and columns

Each folder can be shown as a **details** list or as **icons**, sorted and grouped as you like.
File Manager remembers the choice for each folder, the way Explorer does: set Downloads to icons
grouped by date once, and it opens that way next time. Folders you haven't set up open as a
details list sorted by name.

These choices are kept in File Manager's own settings (in `~/Library/Application Support/File
Manager`), never as hidden files inside your folders, so nothing like `.DS_Store` or
`desktop.ini` is left behind.

## Details and icons

| View | Keys | Also |
|---|---|---|
| as Details | Opt+Cmd+2 | View menu, the toolbar's view buttons, right-click empty space |
| as Icons | Opt+Cmd+1 | the same |

The **details list** has a row per item with columns. The **icon view** shows a grid of icons
with the names under them, and thumbnails for pictures, movies, PDFs and other files Quick Look
can draw. Thumbnails fill in as they're made; until then the file's icon shows.

Everything else works the same in both: Return or F2 renames in place, Space opens Quick Look,
typing a name selects it, Shift+F10 or a right-click opens the menu, files drag in and out, and
a middle-click opens a folder in a new tab. In the icon view the arrow keys move in all four
directions.

## Zoom

| Action | Keys |
|---|---|
| Zoom In | Cmd+=, Cmd+scroll up |
| Zoom Out | Cmd+-, Cmd+scroll down |
| Actual Size | Cmd+0 |

In the icon view, zoom changes the icon size, from 32 to 256 points (64 to start with). In the
details list it makes the icons and rows bigger (16, 24 or 32 points). Cmd+scroll works in the
icon view. Zoom is remembered with the rest of the folder's view; at the largest or smallest
size, File Manager beeps.

## Sorting

Click a column heading in the details list to sort by it, and click again to reverse the order.
**View → Sort By** and **Sort By** on the right-click menu do the same, in either view. Folders
stay at the top unless you turn off **Show folders before files** in [Settings](Settings.md).

## Columns

Right-click the column headings to choose which columns show:

| Column | Shows |
|---|---|
| Name | always shown |
| Date Modified | shown at first |
| Kind | shown at first |
| Size | shown at first; folders show `--` (use Get Info for a folder's size) |
| Date Created | when the item was made |
| Date Added | when it was put in this folder (moved, copied or downloaded here) |
| Extension | `txt`, `jpg`…; handy for sorting by type |
| Permissions | `-rw-r--r--`, as `ls -l` shows it |
| Tags | the item's Finder tags; see [iCloud and tags](iCloud-and-Tags.md) |

Drag a heading to move a column and drag its edge to resize it. Columns are the same in every
folder and are remembered between launches. While searching subfolders a **Folder** column also
shows; see [Searching and selecting](Searching-and-Selecting.md).

## Groups

**View → Group By** (or **Group By** on the right-click menu) splits the folder into groups with
a heading over each, in both views:

| Group By | Groups |
|---|---|
| Kind | Folders, then each kind (PDF document, PNG image…) A to Z |
| Date Modified | Today, Yesterday, Past Week, Past Month, Past Year, Older |
| Size | Folders, Empty, Tiny (under 16 KB), Small, Medium, Large, Huge, Gigantic (over 4 GB), as in Explorer |
| None | no groups |

Items in a group keep the sort order. Each heading shows how many items are in the group.

## The preview pane

Press **Opt+P** (or **View → Preview Pane**, or the toolbar button) to show a preview on the right
of every window. With one item selected it shows a Quick Look preview (pictures, PDFs, text,
movies you can play) and the item's kind, size and dates. With several selected it shows how
many and their total size. Drag the divider to make it wider. Opt+P again hides it.

Unlike Quick Look (Space), the pane stays open while you move through the list.

---
Next: [Searching and selecting](Searching-and-Selecting.md)
