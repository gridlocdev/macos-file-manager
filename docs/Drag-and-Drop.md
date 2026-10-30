# Drag and drop

Drag files and folders to move or copy them: within a window, between File Manager windows, to
and from Finder, the Desktop and other apps. Drags work the way they do in Explorer and Finder.

## Move or copy?

| You drag | It does |
|---|---|
| to a folder on the **same disk** | **moves** |
| to a folder on **another disk** (USB stick, network share) | **copies** |
| holding **Opt** | always **copies** |
| holding **Cmd** | always **moves** |
| back into the folder it's already in | nothing (hold **Opt** to duplicate it) |

The pointer shows a green **+** when the drop will copy. You can press or release Opt and Cmd
while dragging, until you let go.

In Explorer, Ctrl copies and Shift moves. On a Mac the keys are Opt and Cmd, the same as Finder.

## Where you can drop

- **On a folder in the list**: into that folder. It highlights when you're over it.
- **On empty space in the list** (or a file): into the folder you're looking at.
- **On a sidebar item** (Desktop, Downloads, a drive, a folder in the tree…): into that
  place. Dropping **between** pinned folders pins it instead; see [The sidebar](Sidebar.md).
- **On a folder in the address bar** (one of the breadcrumbs): into that folder.
- **Onto another app**: Mail attaches the file, an editor opens it, and so on. Dropping on the
  Trash in the Dock moves it to the Trash.

### Spring-loaded folders

Hold a dragged item over a folder for a moment and the folder opens, so you can go deeper
before dropping. Keep hovering to keep opening folders. This uses the macOS setting in System
Settings → Accessibility → Pointer Control → *Spring-loading* (on by default), including its
delay.

The toolbar works the same way, so you can move a file anywhere without letting go of the mouse:

- Hold over a **breadcrumb** for a second to open that folder (or drop on it to put the file
  there).
- Hold over **Back** or **Forward** for a second to go back or forward; keep holding to go one
  more step each second. You can't drop on these buttons: the pointer shows that a drop there
  does nothing.

### Scrolling while you drag

Hold a dragged item near the top or bottom edge of the list (or the icon view) for a second and
a half and it starts scrolling that way, slowly, until you move away from the edge or let go.
Set the speed in [Settings](Settings.md#files) → *Scroll while dragging*.

## Names that clash and undo

Dropping works exactly like pasting: when names clash you're asked to **Replace**,
**Keep Both** or **Skip**, folders with the same name merge, and **Cmd+Z** undoes the drop.
See [Copying and moving files](Copying-and-Moving-Files.md#when-names-clash).

## What can't be dropped (yet)

Some apps don't hand over a real file but a "promise" to make one: a Mail attachment, a photo
from Photos, an image from Safari. File Manager can't receive those yet; drop them in Finder
or on the Desktop instead.

---
Next: [Views and columns](Views-and-Columns.md)
