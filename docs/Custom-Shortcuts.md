# Custom shortcuts

You can change any shortcut, give one to a command that has none (Compress, say), or take a
shortcut away, with a small text file. File Manager reads it at launch, on top of its standard
shortcuts.

## Editing the file

1. Open **File Manager → Settings → Keyboard** and click **Edit Shortcuts File…**. The first
   time, this makes a starter file and opens it in TextEdit. The file is
   `~/Library/Application Support/File Manager/Shortcuts.json`.
2. Add a line for each command you want to change, using the names in the table below:

   ```json
   {
     "compress": ["Ctrl+Cmd+Z"],
     "rename": ["F2"],
     "goUp": ["Cmd+Up", "Opt+Up"]
   }
   ```

3. Save the file and click **Reload** in Settings. Keys in the file list change straight away;
   the shortcuts shown in the menu bar change the next time you open File Manager. Until then,
   a shortcut the menu bar still shows keeps doing what the menu says.

Each command you list gets exactly the shortcuts you give it, and loses the rest: the example
above makes F2 the only rename key (Return stops renaming) and stops Backspace going up a folder.
An empty list, `"refresh": []`, takes all of a command's shortcuts away. Commands you don't list
keep their standard shortcuts.

If you give a command a shortcut another command has, the other one loses it. Settings lists
each shortcut that moved, and anything in the file that couldn't be used: a misspelt command, or
a shortcut it can't read. Names starting with `_` are ignored, which is how the starter file's
examples stay switched off until you remove the `_`.

## Writing shortcuts

Write them the way the [Keyboard shortcuts](Keyboard-Shortcuts.md) page does: modifiers, then the
key, joined with `+`.

| Part | Written as |
|---|---|
| Modifiers | `Cmd`, `Opt`, `Ctrl`, `Shift` (or `Command`, `Option`, `Alt`, `Control`), in any order |
| Letters, digits, symbols | the key itself: `N`, `2`, `=`, `[`, `.` |
| Other keys | `Return`, `Backspace` (⌫), `Delete` (⌦), `Tab`, `Space`, `Esc`, `Up`, `Down`, `Left`, `Right`, `F1`…`F20` |

Upper and lower case don't matter. For a shifted symbol, write the unshifted key with Shift:
`Shift+Cmd+=`, not `Cmd++`.

Some things to know:

- The menu bar can only show one shortcut per command: the first one with Cmd in it. The others
  still work.
- Keys without Cmd (Return, F2, Delete, Space) act on files only while the file list or icon view
  has the keyboard focus, as the standard ones do.
- Ctrl+Tab and Ctrl+Shift+Tab are handled by macOS itself, so changing **Show Next Tab** and
  **Show Previous Tab** has no effect.
- Cmd+Q, Cmd+W, Cmd+, and the text-editing shortcuts in the address bar aren't File Manager
  commands and can't be changed here.

## Command names

| Name | Command | Standard shortcuts |
|---|---|---|
| `open` | Open | Cmd+O, Cmd+Down, Cmd+Return |
| `newWindow` | New Window | Cmd+N |
| `newTab` | New Tab | Cmd+T |
| `openInNewTab` | Open in New Tab | Ctrl+Return |
| `reopenClosedTab` | Reopen Closed Tab | Shift+Cmd+T |
| `nextTab` | Show Next Tab | Ctrl+Tab |
| `previousTab` | Show Previous Tab | Ctrl+Shift+Tab |
| `showTab1` | Show Tab 1 | Cmd+1 |
| `showTab2` | Show Tab 2 | Cmd+2 |
| `showTab3` | Show Tab 3 | Cmd+3 |
| `showTab4` | Show Tab 4 | Cmd+4 |
| `showTab5` | Show Tab 5 | Cmd+5 |
| `showTab6` | Show Tab 6 | Cmd+6 |
| `showTab7` | Show Tab 7 | Cmd+7 |
| `showTab8` | Show Tab 8 | Cmd+8 |
| `showTab9` | Show Last Tab | Cmd+9 |
| `addToSidebar` | Add to Sidebar | Ctrl+Cmd+T |
| `newFolder` | New Folder | Shift+Cmd+N |
| `newTextFile` | New Text File | Opt+Cmd+N |
| `rename` | Rename | Return, F2 |
| `duplicate` | Duplicate | Cmd+D |
| `getInfo` | Get Info | Cmd+I, Opt+Return |
| `quickLook` | Quick Look | Space |
| `showInFinder` | Show in Finder | (none) |
| `showContextMenu` | Show Context Menu | Shift+F10 |
| `compress` | Compress | (none) |
| `extract` | Extract | (none) |
| `downloadNow` | Download Now | (none) |
| `removeDownload` | Remove Download | (none) |
| `toggleSplitView` | Split View | F3 |
| `copyToOtherPane` | Copy to Other Pane | (none) |
| `moveToOtherPane` | Move to Other Pane | (none) |
| `connectToServer` | Connect to Server… | Cmd+K |
| `moveToTrash` | Move to Trash | Cmd+Backspace, Delete |
| `deleteImmediately` | Delete Immediately… | Opt+Cmd+Backspace, Shift+Delete |
| `putBack` | Put Back | (none) |
| `undo` | Undo | Cmd+Z |
| `redo` | Redo | Shift+Cmd+Z |
| `cut` | Cut | Cmd+X |
| `copy` | Copy | Cmd+C |
| `paste` | Paste | Cmd+V |
| `pasteMove` | Move Items Here | Opt+Cmd+V |
| `copyPath` | Copy Path | Shift+Cmd+C, Opt+Cmd+C |
| `selectAll` | Select All | Cmd+A |
| `invertSelection` | Invert Selection | Shift+Cmd+I |
| `selectByPattern` | Select by Pattern… | Cmd+S |
| `find` | Find | Cmd+F |
| `endSearch` | Clear Search | Esc |
| `goBack` | Back | Cmd+[, Opt+Left |
| `goForward` | Forward | Cmd+], Opt+Right |
| `goUp` | Enclosing Folder | Cmd+Up, Backspace, Opt+Up |
| `goHome` | Home | Shift+Cmd+H |
| `goDesktop` | Desktop | Shift+Cmd+D |
| `goDocuments` | Documents | Shift+Cmd+O |
| `goDownloads` | Downloads | Opt+Cmd+L |
| `goApplications` | Applications | Shift+Cmd+A |
| `goTrash` | Trash | (none) |
| `focusAddressBar` | Go to Location… | Cmd+L, Opt+D |
| `focusNextArea` | Focus Next Area | F6 |
| `focusPreviousArea` | Focus Previous Area | Shift+F6 |
| `refresh` | Refresh | Cmd+R, F5 |
| `toggleHiddenFiles` | Show Hidden Files | Cmd+H, Shift+Cmd+. |
| `viewAsIcons` | as Icons | Opt+Cmd+1 |
| `viewAsDetails` | as Details | Opt+Cmd+2 |
| `zoomIn` | Zoom In | Cmd+=, Shift+Cmd+= |
| `zoomOut` | Zoom Out | Cmd+- |
| `actualSize` | Actual Size | Cmd+0 |
| `togglePreviewPane` | Preview Pane | Opt+P |
| `openTerminal` | Open Terminal Here | Opt+Cmd+T, F4 |

---
Next: [Settings](Settings.md)
