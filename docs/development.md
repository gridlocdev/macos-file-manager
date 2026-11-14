# Development

File Manager is Swift 6 and SwiftUI, built with Swift Package Manager. There's no Xcode project: you can work in VS Code, or any editor, and build from the command line. The rules in `AGENTS.md` at the repository root apply to everyone working on it, and the code layout and how its parts fit together are in [architecture.md](architecture.md).

## Getting set up

You need Xcode (for its Swift toolchain and SDK) and [just](https://github.com/casey/just).

```bash
just build           # compile (debug)
just test            # run the unit tests
just run             # build a debug File Manager.app and open it
just run-attached    # same, with logs in the terminal
just bundle [config] # build build/File Manager.app (release by default, or debug)
just install         # release build into ~/Applications, updated in place
just dist            # release build zipped as build/File-Manager-<version>.zip
just snapshot [keys] [out] # debug build: open a demo folder, press keys, save a PNG (see Snapshots)
just screenshot      # open a sample home folder in dark mode for the README picture
just screenshot-save <png> # turn that screenshot into docs/images/window.webp
just icons           # regenerate the app icon (needs Inkscape)
just fmt             # format with swift-format
just clean           # delete .build and build
```

Recipes call `xcrun swift`, Xcode's toolchain. A toolchain installed with swiftly can fail against the current macOS SDK, so don't use bare `swift`.

### VS Code

Install the recommended extensions (Swift and just) when VS Code offers them, then choose the Xcode toolchain: Command Palette → **Swift: Select Toolchain**.

- **Run and Debug** (F5 in VS Code) has *Debug FileManagerApp* and *Release FileManagerApp*. They run the bare executable, not the `.app` bundle. That works: `Info.plist` is embedded in the executable, so the menu bar still says *File Manager*, but there's no app icon and Help opens the repo's `docs/` instead of the bundled copy.
- **Terminal → Run Task** has `just build`, `just test`, `just run` and `just install`. Cmd+Shift+B builds.

## Checking your work

Run both after every change:

```bash
just build   # compile (debug)
just test    # run the unit tests
```

`just test` runs Swift Testing suites for everything in `FileManagerCore`: keymap lookups and conflicts, history, path resolution and completion, sorting, file operation planning, name patterns and search filters, and batch rename previews and moves. Put new pure logic in `FileManagerCore` and test it there; keep AppKit in the app target.

Two tests read the docs: `docs/controls.md` must list every shortcut of every action, and `docs/custom-shortcuts.md` must list every action name. Update them in the same change as the keymap.

It also runs `FileManagerAppTests`, which test the app's models (`BrowserModel`, `FileOperations`) through `@testable import FileManagerApp`. Each test makes a `Sandbox`: a scratch folder in the temporary directory, a `BrowserServices` whose stores, session and settings use their own UserDefaults suite and files in that folder, a private pasteboard, a Trash inside the folder, and a `FakePresenter` that answers confirmations and counts beeps. `FileOperations` reports errors to the sandbox instead of a modal alert, which would hang the run. Nothing touches your folders, Trash or settings. Folder reads and file operations finish in the background, so tests wait with `eventually { … }`.

### Snapshots

Debug builds have a hook (`DebugSnapshot.swift`) that draws the window into a PNG, prints the whole menu bar with shortcuts and enabled state, and quits. It works without screen-recording permission. The output ends with which view has the keyboard focus:

```bash
just snapshot                                    # build/snapshot.png of a demo folder
just snapshot "Backspace,Opt+Left,Cmd+H" out.png # press keys first, then capture
just snapshot "menu:New Folder,type:Reports,Return,Cmd+Z" out.png
```

Steps are key chords, `menu:<item title>`, `type:<text>`, `action:<Action raw value>` (runs it on the window's model directly), `scope:subfolders` (Find's switch), `batch:<find>><replace>` (a batch rename of the selection, as the sheet's Rename button runs it), `mouse:<x>/<y>` (a click at window points from the top-left; the PNG is at 2x) and `click:list` (makes the file list first responder through AppKit, as a click does, behind SwiftUI's back). When you're using another app, macOS may not let File Manager become active; then nothing is key, Cmd shortcuts don't reach the menu bar, and the hook falls back to the first window, so use `action:` steps. The output lists the items shown and selected at the end.

Snapshot runs stay inside the demo folder so a fresh build never triggers macOS's folder-access prompts: the window starts there instead of Home, the sidebar's folder tree is rooted there, Locations lists no disks, and your saved session, recent folders, folder views and shortcuts file are neither read nor written. To try opening folders from outside (`open -a`), send them only while a snapshot instance is running; otherwise `open` starts a normal copy of the app. Keys go through the normal event queue, so they exercise `KeyMonitor` and the menu bar like real key presses. Shifted Cmd shortcuts (Shift+Cmd+N) don't match menus when synthesized; use `menu:` for those. The demo folder (`build/snapshot-demo`) is recreated each run, and the hook refuses to press anything once the window has left it, so a test can't touch real files. Undoing a copy or a new folder moves it to the real Trash. The app is launched with `open`, so it becomes the active app; Cmd shortcuts only reach the menu bar of the active app.

## The README picture

`just screenshot` makes a sample home folder (`build/screenshot/alex`, with Documents full of made-up files), opens it in dark mode at 1100×620 and leaves the window up. The sidebar and address bar show the sample folder as Home, so none of your own folders or names appear. Take the picture yourself (Shift+Cmd+4, Space, then Opt-click the window to leave out its shadow), quit the app, and run `just screenshot-save <file.png>` to write `docs/images/window.webp`. The snapshot hook can't draw it: the sidebar's Liquid Glass rows come out dim or black in an image drawn by the app.

## Adding a shortcut or action

How a key press reaches an action is described in [How a shortcut runs](architecture.md#how-a-shortcut-runs).

1. Add a case to `Action` with its `title` and `menu`.
2. Add its chords to `Keymap.standard`.
3. Handle it in `BrowserModel.perform`, and say when it's available in `Action.isAvailable(in:)` (the switch lists every case, so it won't compile until you do).
4. Put it in a menu in `AppCommands`.
5. Add a row to `docs/controls.md` whose first cell is the title and second cell lists every chord in `KeyChord.description` spelling (modifiers in the order Ctrl, Opt, Shift, Cmd). `KeymapTests.shortcutsPageMatchesKeymap` fails until the page matches.
6. Add its name (the `Action` raw value, in backticks) to `docs/custom-shortcuts.md`. `docsListEveryActionName` fails until the page lists it.

`KeymapTests.noChordIsBoundTwice` catches clashes.

## App icon

The icon is drawn by hand in `assets/icon.svg`: a white standing set of drawers on a blue gradient tile, on Apple's 1024 icon grid (an 824-unit tile at 100,100 with a transparent margin). The gaps and handles use the tile's gradient so they read as cut out of the cabinet.

After editing the SVG, run `just icons` (needs Inkscape: `brew install --cask inkscape`). It regenerates `Resources/AppIcon.icns` and `assets/icon/icon.png` (the README's icon), which are committed so builds don't need Inkscape.

## Signing

`scripts/bundle.sh` signs with the first Apple Development or Developer ID identity in your keychain, or ad hoc (`-`) if there isn't one. Override with `SIGN_IDENTITY="…" just install`. `just install` waits for the running copy to quit, then updates `~/Applications/File Manager.app` in place with `rsync -a --delete` and re-registers it with LaunchServices. Deleting it and copying a new one left a Dock pin pointing at the deleted app, since the Dock follows the app folder itself, not just its path. rsync writes each changed file anew, which matters for the executable: the kernel caches code signatures per file, so overwriting one in place gets it killed. With ad-hoc signing, macOS may treat each rebuild as a new app and ask for folder access again.

## Continuous integration and releases

`.github/workflows/ci.yml` builds and runs the tests on every push to `main` and every pull request, on GitHub's `xcode-27` runner (macOS 27 with Xcode 27; the app needs the macOS 27 SDK).

To release, bump `CFBundleShortVersionString` in `Resources/Info.plist`, commit, and push a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

`.github/workflows/release.yml` runs the tests, builds the app with the tag as its version (`APP_VERSION`, without the `v`), zips it as `File-Manager-<version>.zip` and publishes a GitHub release with it and generated notes. A tag with a hyphen (`v1.1.0-beta.1`) makes a pre-release. The build is Apple Silicon only (macOS 27 doesn't run on Intel) and signed ad hoc, not notarized, so the first launch needs **Open Anyway** (see [Getting started](getting-started.md#the-first-time-you-open-it)). `just dist` makes the same zip locally.
