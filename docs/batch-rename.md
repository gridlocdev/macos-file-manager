# Batch rename

Select several items and press **Return** or **F2** (or **File → Rename**) to rename them all at
once. A window shows each name next to its new name as you change the options, so you can see
the result before anything is renamed.

## The options

They apply in this order, to the name without its extension:

| Option | What it does | Example |
|---|---|---|
| New name | replaces each name (leave empty to keep the names) | *Holiday* |
| Find / Replace with | replaces text in the name | *IMG* → *Photo* |
| Match case | Find only matches the same capitals | |
| Regular expression | Find is a regular expression; Replace can use `$1`, `$2`… for its groups | `(\d+)-(\d+)` → `$2-$1` |
| Case | lowercase, UPPERCASE or Title Case | |
| Numbers | adds a number before or after the name, counting in list order | *Holiday 01*, *Holiday 02* |
| Start at, Digits, Separator | the first number, how many digits (padded with zeros), and what goes between number and name | 1, 2, a space |
| Change extensions too | Find, Replace and Case also work on the extension | *.JPG* → *.jpg* |

For example, to name a set of photos *Holiday 01.jpg*, *Holiday 02.jpg* and so on: type
*Holiday* in **New name**, set **Numbers** to *After Name* and **Digits** to 2. The numbers
follow the order of the list, so sort it first (by Date Modified, say) to number the photos in
the order they were taken.

## Problems

A new name shows in red, with the reason under it, when it:

- is empty, or contains `/` or `:`,
- is the same as another item's new name in the same folder,
- is already used by something else in the folder.

**Rename** stays off until every problem is fixed and at least one name changes. An invalid
regular expression is reported above the list. Names that don't change are shown in grey and
left alone.

Items can swap names (*a* to *b* and *b* to *a*): File Manager gives them temporary names first,
so nothing is overwritten.

## Undo

The whole batch is one action: a single **Cmd+Z** puts every name back, and **Shift+Cmd+Z**
renames them again. Batch rename works on results from a subfolder search too, with items in
different folders; names only clash within the same folder.

---
Next: [Tabs and windows](Tabs-and-Windows.md)
