# Searching and selecting

Find narrows the list to the items you're after, in the current folder or in every folder
inside it. The selection commands pick out items by name without clicking through a long list.

## Finding in this folder

Press **Cmd+F** (or **Edit → Find**). A find bar opens above the list:

```
 🔍 report             [ This Folder | Subfolders ]  Filters ▾   ⓧ
```

As you type, the list shows only the items whose names match, and the status bar says how many
of the folder's items are left: *3 of 40 items*. Everything else still works on what's shown:
Return renames, Cmd+C copies, Delete trashes. Items the filter hides are never selected, so
nothing you can't see gets trashed.

- **Down arrow** or **Return** in the find field goes to the list and selects the first result.
- **Cmd+F** again puts the cursor back in the field with the text selected.
- **Esc** in the find field or in the list closes the find bar and shows the whole folder again.
- Opening a folder or going anywhere else closes it too.

## What you can type

| You type | It finds |
|---|---|
| `report` | names containing *report*, anywhere in the name |
| `*.pdf` | names ending in *.pdf* |
| `IMG_????.jpg` | *IMG_* then exactly four characters, then *.jpg* |
| `*.jpg; *.png` | either pattern |

Upper and lower case don't matter. A `*` stands for any run of characters and a `?` for one
character; with either in it, the pattern has to match the whole name. Several patterns are
separated with `;`.

## Searching subfolders

Click **Subfolders** in the find bar to look in every folder inside the current one as well.
Results come in as they're found, with a spinner and *Searching… 120 found* in the status bar.
A **Folder** column shows where each result is, relative to the folder you searched from; hover
over it for the full path.

Two searches run together and their results are merged:

- **Spotlight** answers straight away for folders macOS has indexed (your home folder, most
  disks).
- A **walk** through the folders finds what Spotlight leaves out: ~/Library, disks that aren't
  indexed, network drives, and files made a moment ago.

The search skips the insides of packages such as apps, as the list does. Hidden files and
folders are only searched while hidden files are shown (Cmd+H). A search stops at 5,000 results;
the status bar says so when it does. Type more of the name to narrow it down.

You can work on results as in a folder: open, rename, copy, trash, Get Info. Opening a folder in
the results goes to that folder and closes the find bar.

## Filters

**Filters** in the find bar narrows the results by:

| Filter | Choices |
|---|---|
| Kind | Folders, Documents, Images, Music and Audio, Movies, Archives, Applications |
| Date Modified | Today, Past Week, Past Month, Past Year |
| Size | Under 1 MB, 1 MB to 100 MB, Over 100 MB (files only) |

Filters work in this folder and in subfolders, and with no name typed: choose **Subfolders**,
**Images** and **Past Week** to see every recent picture below the folder. The button shows how
many filters are on, *Filters (2)*, and **Clear Filters** turns them all off. Kind goes by the
file's extension.

## Selecting

| Command | Keys | What it does |
|---|---|---|
| Select All | Cmd+A | selects everything in the list |
| Invert Selection | Shift+Cmd+I | selects what wasn't selected, and deselects what was |
| Select by Pattern… | Cmd+S | selects items whose names match a pattern |

**Select by Pattern** asks for a pattern, written the same way as in Find (`*.jpg; *.png`).
**Select** replaces the selection with the matching items; **Add to Selection** keeps what was
already selected. It remembers the last pattern you used. If nothing matches you'll hear a beep.

These work on what the list is showing, so with Find open they only pick from the results.

To select by typing, type the start of a name in the list; File Manager jumps to the first item
that starts with those letters.

---
Next: [Batch rename](Batch-Rename.md)
