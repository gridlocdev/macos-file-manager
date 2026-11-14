# Tabs and windows

Each tab shows one folder, with its own Back/Forward history and selection. Tabs are ordinary macOS window tabs, so everything the tab bar does elsewhere on your Mac works here too.

## Opening tabs

| To | Do this |
|---|---|
| Open a new tab on the same folder | **Cmd+T** |
| Open a folder in a new tab | **middle-click** it, or select it and press **Ctrl+Return**, or right-click → **Open in New Tab** |
| Open a sidebar place in a new tab | right-click it → **Open in New Tab** |
| Open a new window on the same folder | **Cmd+N** |

Folders opened with middle-click or Ctrl+Return open **in the background**, like links in a browser, so you can open several and keep going.

The tab bar appears as soon as there are two tabs. To always show it, choose **View → Show Tab Bar**.

## Switching and closing

- **Ctrl+Tab** and **Ctrl+Shift+Tab** go to the next and previous tab.
- **Cmd+1** to **Cmd+8** go to that tab, **Cmd+9** to the last one. On layouts whose number row needs Shift for digits (French AZERTY), press Cmd and the key without Shift, as for any Mac app.
- **Cmd+W** closes the tab (or the window, if it's the last tab).
- **Shift+Cmd+T** reopens the most recently closed tab, in the folder it was showing. It remembers the last 20.

## Moving tabs around

- Drag a tab along the tab bar to reorder it.
- Drag a tab **out of the bar** to make it its own window, or onto another window's tab bar to move it there.
- **Window → Merge All Windows** puts every window's tabs into one window.
- **Window → Show All Tabs** (Shift+Cmd+\\) shows every tab as a thumbnail.

Dragging files **onto a tab** isn't supported; drop them on a sidebar place instead, or switch to the tab first (hovering a file over a folder in the list opens it).

## Split view

Press **F3** (or **View → Split View**, or the toolbar's split button) to show two folders side by side in one window, as in Dolphin. The new pane opens on the same folder; F3 again closes the split, keeping the folder of the pane you were in. While split, the tab (and the Window menu) shows both folders, left first: *Documents + Downloads*.

```
┌─────────┬───────────────────┬───────────────────┐
│ Sidebar │ ▌Documents        │  Downloads        │
│         │  file list        │  file list        │
│         │  status bar       │  status bar       │
└─────────┴───────────────────┴───────────────────┘
```

Each pane has its own folder, history, view, selection and find bar. The **active pane** is the one you last clicked in or moved the keyboard to; its heading is highlighted. The toolbar's Back, Forward, Up and address bar, the sidebar, the menu bar and the preview pane all work on the active pane.

| To | Do |
|---|---|
| Move between the panes | click in one, or press **F6** (left list → right list → address bar → sidebar) |
| Copy the selection to the other pane's folder | **Edit → Copy to Other Pane**, or right-click |
| Move it there | **Edit → Move to Other Pane**, or right-click |
| Copy or move with the mouse | drag from one pane to the other (Opt copies, Cmd moves) |

Copy and Move to Other Pane have no shortcut by default (F5 and F6, which Total Commander uses, are Refresh and Focus Next Area here). Give them one in [your shortcuts file](custom-shortcuts.md), for example `"copyToOtherPane": ["Shift+F5"]`.

Split panes aren't reopened after quitting; each tab comes back as one pane.

## Reopening where you left off

When you quit and open File Manager again, your windows and tabs come back, each in the folder it was showing, with the same tab selected. Minimized windows come back too, and so do your windows if you quit while File Manager is hidden. Folders that no longer exist are skipped. Back and Forward history and the selection aren't kept.

Turn this off in [Settings](settings.md) → **Reopen windows and tabs from last time**; then File Manager starts with one window on your home folder.

If macOS asks whether to reopen windows after a restart, that's separate: File Manager reopens its own tabs either way.

---
Next: [The sidebar](sidebar.md)
