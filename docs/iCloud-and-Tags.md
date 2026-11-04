# iCloud and tags

## iCloud Drive

iCloud Drive is in the sidebar under Pinned (when you're signed in to iCloud). It lists what
Finder does: your Desktop and Documents folders when they're kept in iCloud, and the folders
apps keep there (Numbers, TextEdit, Shortcuts…) under the app's name. An app's folder shows
up once it has something in it. Items that are
only in iCloud, not on this Mac, show a cloud after the name in the details list and on the
icon in the icon view:

| Symbol | Means |
|---|---|
| (none) | downloaded and up to date |
| cloud with a down arrow | in iCloud only; opening it downloads it |
| circle with a dotted arrow | downloading |
| cloud with an up arrow | uploading |

Select items and use **File → Download Now** to download them without opening them, or
**File → Remove Download** to free the space they take on this Mac while keeping them in iCloud.
Both are on the right-click menu too, when they apply. The list updates as the download goes,
and so does a file downloaded by opening it (double-click, Open With, any way): its cloud
goes away once it's on this Mac. Press F5 if it seems stuck.

Download Now and Remove Download change only what's kept on this Mac, not the files, so they
aren't on the undo list.

## Finder tags

Tags are Finder's coloured labels. File Manager shows and sets the same tags, so they stay in
step with Finder, Spotlight and other apps.

**Seeing tags.** Tagged items show up to three coloured dots after the name (on the icon in the
icon view). Your Desktop, Documents and Downloads folders show none in your home folder: macOS
asks for access to a folder before an app reads its tags, and listing Home shouldn't ask. Hover over the dots for the tag names. Right-click the column headings to add a
**Tags** column, and click its heading to sort by tag.

**Tagging.** Select items, right-click, and choose a tag from **Tags**. A tick means every
selected item has it; choosing it again takes it off them all. A dash means only some have it;
choosing it puts it on all of them. **New Tag…** adds a tag that isn't in the list. Tag
changes go on the undo list: Cmd+Z puts the old tags back.

The list shows Finder's seven colours, then any other tags used in the folder. Tags without one
of the seven colour names show grey.

**Finding by tag.** In the find bar (Cmd+F), **Filters → Tag** shows only items with that tag,
in this folder or in its subfolders. See [Searching and selecting](Searching-and-Selecting.md).

## Zip archives

**File → Compress** (or right-click → **Compress**) zips the selection next to it: one item
gives `name.zip` (`notes.txt.zip` for a file), several give `Archive.zip`. Items from several
folders (subfolder search results) go in an archive in the folder you searched from. **File → Extract**
opens a selected `.zip` next to itself: a single item inside comes out under its own name, and
anything else goes in a folder named after the archive. Neither replaces anything: names that are
taken get ` (2)`. Both show in the progress window for big archives, and Cmd+Z moves what was
made to the Trash.

They use the same tool as Finder (`ditto`), so tags and other Mac details survive the round
trip. Double-clicking a zip opens it with Archive Utility, as in Finder.

---
Next: [Custom shortcuts](Custom-Shortcuts.md)
