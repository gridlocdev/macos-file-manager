# Installing

File Manager needs **macOS 27 or later**.

There are no prebuilt downloads, so you build it from the source code. That needs two things:

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

If you build without an Apple developer certificate, the app is signed "ad hoc" and macOS may
treat each rebuild as a new app, so the prompts can come back after `just install`. See
[Troubleshooting](Troubleshooting.md#the-permission-prompts-came-back).

## Updating

Pull the latest code and run `just install` again. It quits the running copy, replaces it, and
opens the new one. Your settings are kept.

## Making a copy to share

`just dist` builds a release copy and zips it as `build/File-Manager-<version>.zip`. Whoever
unzips it gets the same Gatekeeper warning as above the first time they open it, because the
app isn't notarized.

## Uninstalling

1. Quit File Manager (Cmd+Q).
2. Delete `~/Applications/File Manager.app`.

Settings are stored under `dev.gridloc.file-manager`. To remove them too:
`defaults delete dev.gridloc.file-manager`.

---
Next: [Using the app](Using-the-App.md)
