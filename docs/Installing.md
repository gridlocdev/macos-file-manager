# Installing

File Manager needs **macOS 27 or later** on a Mac with Apple Silicon.

## Downloading

Downloads are on the project's GitHub **Releases** page. Get `File-Manager-<version>.zip`,
unzip it, and move **File Manager.app** to your Applications folder.

### The first time you open it

The app isn't notarized by Apple, so macOS won't open it the first time and says Apple can't
check it for malicious software. You only need to get past this once:

1. Try to open the app, and close the warning.
2. Open **System Settings → Privacy & Security**, scroll down to the message about File
   Manager, click **Open Anyway**, and confirm with your password or Touch ID.

Or, in Terminal: `xattr -dr com.apple.quarantine "/Applications/File Manager.app"`, then open
the app normally.

## Building it yourself

You need two things:

- **Xcode**, from the Mac App Store. Open it once after installing so it can finish setting up.
- **[just](https://github.com/casey/just)**, a small command runner: `brew install just`.

Then, in Terminal, from the project folder:

```bash
just install
```

`just install` builds a release copy, puts **File Manager.app** in `~/Applications`, and opens it.

## Permission prompts

The first time you open your Desktop, Documents or Downloads folder, or a network or removable
volume, macOS asks whether File Manager may access it. Click **Allow**. If you clicked
**Don't Allow**, the folder shows *Can't Open Folder*; turn access back on in System Settings →
Privacy & Security → **Files & Folders** → File Manager.

To skip the prompts entirely, and to open folders that are otherwise off limits (other apps'
data in `~/Library`, for example), give File Manager **Full Disk Access** in System Settings →
Privacy & Security → Full Disk Access. This is optional.

Downloaded copies and copies you build without an Apple developer certificate are signed "ad
hoc", and macOS may treat each new version as a new app, so the prompts can come back after an
update. See
[Troubleshooting](Troubleshooting.md#the-permission-prompts-came-back).

## Updating

Download the new version and replace the old **File Manager.app** with it. If you build it
yourself, pull the latest code and run `just install` again: it quits the running copy,
updates it in place, and opens the new one, so File Manager stays pinned in the Dock. Either
way, your settings are kept.

## Uninstalling

1. Quit File Manager (Cmd+Q).
2. Delete **File Manager.app** from Applications (or `~/Applications` if you built it).

Settings are stored under `dev.gridloc.file-manager`. To remove them too:
`defaults delete dev.gridloc.file-manager`.

---
Next: [Using the app](Using-the-App.md)
