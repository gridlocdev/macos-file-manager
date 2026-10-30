# Troubleshooting

## Common questions

**A folder shows "Can't Open Folder".**
macOS is blocking access, usually because **Don't Allow** was clicked on its prompt (it doesn't
ask again). The message says which switch to turn on, and its button opens that page of System
Settings; turn the switch on, then click **Try Again** (or press F5). For Desktop, Documents,
Downloads and removable or network drives that's Privacy & Security → **Files & Folders** →
File Manager. Other folders the system guards (other apps' data in `~/Library`, the Trash) need
**Full Disk Access**. A few system folders can't be opened by any app. To have macOS ask again
instead, run `tccutil reset SystemPolicyDesktopFolder dev.gridloc.file-manager` in Terminal
(or `SystemPolicyDocumentsFolder`, `SystemPolicyDownloadsFolder`). See
[Installing](Installing.md#permission-prompts).

<a id="the-permission-prompts-came-back"></a>
**The permission prompts came back.**
Downloaded copies, and copies built without an Apple developer certificate, are signed ad
hoc, and macOS can treat each new version as a new app. Allow access again, or give it Full
Disk Access once. If you
have an Apple Development certificate in your keychain, the build uses it and macOS remembers
your answers across rebuilds.

**F4 / F5 / F6 change the brightness or volume instead.**
On a MacBook, hold **fn**, or switch the top row to standard function keys. See
[Coming from Windows and Linux](Coming-from-Windows-and-Linux.md#function-keys-on-a-macbook).
Every one also has a Cmd shortcut: Opt+Cmd+T, Cmd+R, and Tab.

**Go → Trash says it needs Full Disk Access.**
macOS only lets apps look inside the Trash with Full Disk Access. Turn it on for File Manager
in System Settings → Privacy & Security → Full Disk Access, or use Finder for the Trash.

**Put Back says it can't put an item back.**
It only knows where items came from if File Manager moved them to the Trash. Use Put Back in
Finder for the others.

**Move to Trash failed on a network drive or USB stick.**
Some drives have no Trash. Use **Delete Immediately…** (Opt+Cmd+Backspace) instead, which
deletes for good after asking.

**Cmd+Z didn't undo what I expected.**
There's one undo history for the whole app, so it undoes the most recent change in any window.
While you're typing in the address bar or renaming, Cmd+Z undoes typing instead.

**Delete doesn't trash anything.**
The key labelled *delete* on a Mac is Backspace, which goes up a folder. Use Cmd+Backspace, or
forward Delete (fn+delete on a MacBook). Forward Delete only works while the file list has the
focus.

**I can't drop an attachment from Mail, or a photo from Photos.**
Those apps hand over a promise to make a file rather than the file itself, and File Manager
can't receive those yet. Drop them in Finder or on the Desktop. See
[Drag and drop](Drag-and-Drop.md#what-cant-be-dropped-yet).

**A drag copied when I wanted it to move (or the other way round).**
Between disks a drag copies, on the same disk it moves. Hold Cmd to move or Opt to copy. See
[Drag and drop](Drag-and-Drop.md#move-or-copy).

**Space doesn't open Quick Look.**
The file list needs the keyboard focus (click a file first), and something must be selected.

**Get Info says "Calculating…" for a long time.**
It's adding up every file in the folder. Big folders, or folders on network drives, take a
while. Closing the window stops it.

**My tabs didn't come back after quitting.**
Check Settings → **Reopen windows and tabs from last time**. Folders that were deleted or are on
a disconnected drive are skipped. If the app crashed instead of quitting, the tabs from just
before the crash come back.

**Ctrl+Tab doesn't switch tabs.**
It switches tabs within one window. Tabs in separate windows aren't in the same tab bar; use
Window → Merge All Windows to put them together.

**A drive won't eject.**
Something is still using it: a file open in another app, a Terminal in a folder on it, or a
File Manager tab showing it. Close those and try again.

**Cmd+H showed hidden files instead of hiding the app.**
That's on purpose. Use File Manager → Hide File Manager, or click another app.

**Return doesn't open the file.**
Return is kept for renaming, as on a Mac. Open with Cmd+O, Cmd+Down, Cmd+Return or a
double-click.

**Open Terminal Here says "No terminal app found".**
The app chosen in [Settings](Settings.md) isn't installed, or was moved. Pick another one.

**The list didn't update after I changed a file.**
It updates when files are added, removed or renamed in the folder you're looking at. Changes
inside a file (its size or date) may not show until you press F5 or Cmd+R. Network shares may
not report changes at all; refresh by hand there.

**iCloud Drive files show a small size.**
Files that are only in iCloud and not downloaded to this Mac take up almost no space locally.
Open the file to download it.

**The app icon in the Dock is blank or old.**
That's the macOS icon cache after a rebuild. It sorts itself out after the app is moved, or
after logging out and back in.

---
Back to [Home](Home.md)
