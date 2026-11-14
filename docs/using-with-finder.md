# Using with Finder

File Manager works alongside Finder rather than replacing it. macOS doesn't let another app
take over everything Finder does, so some things always open in Finder. This page says which,
and the ways to get folders into File Manager instead.

## Opening folders in File Manager

| From | How |
|---|---|
| Finder | right-click a folder → **Open With → File Manager** |
| Finder and other apps | select files or folders, then **Services → Open in File Manager** (in the app's menu or the right-click menu) |
| The Dock | drag a folder onto File Manager's Dock icon |
| Terminal | `open -a "File Manager" .` (or any path) |

Each folder opens in a new window, even if you've closed every File Manager window. A file
opens its folder, with the file selected.

If **Open in File Manager** isn't in the Services menu, turn it on in System Settings →
Keyboard → Keyboard Shortcuts → Services → Files and Folders. You can give it a shortcut there
too, which makes it work from any app.

File Manager is listed under Open With but isn't made the default for folders, so
double-clicking a folder on the desktop still opens Finder.

## What still opens in Finder

| Where | Why |
|---|---|
| The desktop and its icons | the desktop is drawn by Finder |
| Folders and stacks in the Dock ("Open in Finder") | the Dock always hands these to Finder |
| **Show in Finder** / **Reveal** in other apps, Spotlight's Cmd+Return, downloads in Safari | these ask for Finder by name |
| Double-clicking a folder in Finder or on the desktop | Finder handles its own windows |
| AirDrop and browsing the network for servers | not in File Manager |

## Connecting to a server

**Go → Connect to Server…** (**Cmd+K**, as in Finder) mounts a shared folder on another
computer or a NAS and opens it. Type an address:

| Server | Address |
|---|---|
| Windows share, NAS, Samba (SMB) | `smb://nas.local/share`, `nas.local/share`, `192.168.1.20/share`, `[fe80::1]/share` (IPv6), or `\\nas\share` as on Windows (`smb:\\nas\share` works too) |
| NFS | `nfs://server/export` |
| WebDAV | `https://dav.example.com/files` |

macOS asks for the name and password itself and can keep them in your keychain. A share that's
already mounted (by Finder, say) opens straight away. Mounted shares show under Locations in the
sidebar with an Eject button, and the last ten addresses are listed in the window for next
time. If you type a password into the address (`smb://name:password@nas/share`), it's used to
connect but left out of that list; let macOS keep it in the keychain instead.

WebDAV needs an `https://` address. Plain `http://` is refused because it would send your
password and files unencrypted; most servers answer on `https://` too.

SFTP isn't on the list: macOS can't mount SFTP servers by itself. Use an app such as Cyberduck
or macFUSE with SSHFS to mount one, then open the mounted folder in File Manager.

## Going the other way

**File → Show in Finder** (also on the right-click menu) opens the selected items in a Finder
window, for the few things only Finder does, such as burning a disc or using Finder extensions
from other apps.

Everything File Manager does to files (copy, move, rename, trash, tags) is a normal change on
disk, so Finder shows the result straight away, and the other way round. Put Back, though, only
knows about items File Manager trashed; see
[Copying and moving files](Copying-and-Moving-Files.md#the-trash-and-put-back).

---
Next: [iCloud and tags](iCloud-and-Tags.md)
