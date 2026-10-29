# Troubleshooting

## Common questions

**A folder shows "Can't Open Folder".**
macOS is blocking access. For Desktop, Documents, Downloads and removable or network drives,
allow File Manager in System Settings → Privacy & Security → **Files & Folders**. Some folders
(other apps' data in `~/Library`, for example) need **Full Disk Access**. A few system folders
can't be opened by any app. See [Installing](Installing.md#permission-prompts).

<a id="the-permission-prompts-came-back"></a>
**The permission prompts came back.**
If you build without an Apple developer certificate, the app is signed ad hoc, and macOS can
treat each rebuild as a new app. Allow access again, or give it Full Disk Access once. If you
have an Apple Development certificate in your keychain, the build uses it and macOS remembers
your answers across rebuilds.

**F4 / F5 / F6 change the brightness or volume instead.**
On a MacBook, hold **fn**, or switch the top row to standard function keys. See
[Coming from Windows and Linux](Coming-from-Windows-and-Linux.md#function-keys-on-a-macbook).
Every one also has a Cmd shortcut: Opt+Cmd+T, Cmd+R, and Tab.

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
