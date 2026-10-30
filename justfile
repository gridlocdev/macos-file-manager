# File Manager — SwiftUI app built with SwiftPM + Xcode's toolchain (no .xcodeproj).

app := "build/File Manager.app"

default:
    @just --list

# Compile (debug) with Xcode's Swift toolchain
build:
    xcrun swift build

# Run the unit tests (Core logic and docs; the app's models in a scratch sandbox)
test:
    xcrun swift test

# Build the .app bundle (debug|release)
bundle config="release":
    scripts/bundle.sh {{config}}

# Build a debug bundle and launch it
run: (bundle "debug")
    pkill -x FileManagerApp || true
    open "{{app}}"

# Launch the bundle with logs in this terminal
run-attached: (bundle "debug")
    pkill -x FileManagerApp || true
    "{{app}}/Contents/MacOS/FileManagerApp"

# Install a release build to ~/Applications
install: (bundle "release")
    pkill -x FileManagerApp || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/"File Manager.app"
    cp -R "{{app}}" ~/Applications/
    open ~/Applications/"File Manager.app"
    @echo "Installed ~/Applications/File Manager.app"

# Release build zipped for sharing: build/File-Manager-<version>.zip (what a release publishes)
dist: (bundle "release")
    #!/usr/bin/env bash
    set -euo pipefail
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "{{app}}/Contents/Info.plist")"
    zip="build/File-Manager-$version.zip"
    rm -f "$zip"
    ditto -c -k --sequesterRsrc --keepParent "{{app}}" "$zip"
    echo "Made $zip"

# Debug bundle: open a demo folder, press keys (e.g. "Backspace,Cmd+H"), save a PNG, print menus
snapshot keys="" out="build/snapshot.png": (bundle "debug")
    rm -rf build/snapshot-demo
    mkdir -p build/snapshot-demo/Projects build/snapshot-demo/Receipts build/snapshot-demo/.config
    printf 'hi\n' > build/snapshot-demo/notes.txt
    printf 'x\n' > build/snapshot-demo/file2.txt
    printf 'x\n' > build/snapshot-demo/file10.txt
    printf 'x\n' > build/snapshot-demo/Projects/plan.txt
    printf 'x\n' > build/snapshot-demo/Receipts/receipt-01.txt
    printf 'x\n' > build/snapshot-demo/Receipts/receipt-02.txt
    cp assets/icon/icon.png build/snapshot-demo/drawers.png
    pkill -x FileManagerApp || true
    rm -f build/snapshot.log
    open -W -n --stdout "$PWD/build/snapshot.log" --stderr "$PWD/build/snapshot.log" --env FILEMANAGER_SNAPSHOT="$PWD/{{out}}" --env FILEMANAGER_SNAPSHOT_FOLDER="$PWD/build/snapshot-demo" --env FILEMANAGER_SNAPSHOT_KEYS="{{keys}}" "{{app}}"
    cat build/snapshot.log

# The README picture: opens a sample home folder in dark mode and leaves it up to screenshot
# (Shift+Cmd+4, Space, Opt-click the window: no shadow). Then: just screenshot-save <png>
screenshot: (bundle "debug")
    #!/usr/bin/env bash
    set -euo pipefail
    # A sample home folder, so the picture shows none of your own folders or names.
    home="$PWD/build/screenshot/alex"
    docs="$home/Documents"
    rm -rf build/screenshot
    mkdir -p "$home"/{Desktop,Downloads,Music,Pictures} "$docs"/{Invoices,Photos,Projects,Recipes,"Taxes 2026"}
    file() { mkfile -n "$2" "$docs/$1"; touch -t "$3" "$docs/$1"; }
    file "Budget 2026.numbers" 48k 202610270915
    file "Cover Letter.pages" 212k 202610221430
    file "Floor Plan.pdf" 1228k 202609301010
    file "Meeting Notes.md" 4k 202610290840
    file "Trip Itinerary.docx" 36k 202610121955
    file "Backup.zip" 25600k 202608151200
    cp assets/icon/icon.png "$docs/Holiday Card.png"
    touch -t 202610241805 "$docs/Holiday Card.png"
    touch -t 202610281130 "$docs"/*/
    pkill -x FileManagerApp || true
    open -n --env FILEMANAGER_SNAPSHOT=unused --env FILEMANAGER_SNAPSHOT_STAY=1 \
        --env FILEMANAGER_SNAPSHOT_FOLDER="$docs" --env FILEMANAGER_SNAPSHOT_HOME="$home" \
        --env FILEMANAGER_SNAPSHOT_APPEARANCE=dark --env FILEMANAGER_SNAPSHOT_SIZE=1100x620 "{{app}}"
    echo "Screenshot the window, quit File Manager, then: just screenshot-save <file.png>"

# Turn a screenshot of the window into the README picture, docs/images/window.webp (needs cwebp)
screenshot-save png:
    cwebp -quiet -q 90 "{{png}}" -o docs/images/window.webp
    @echo "Wrote docs/images/window.webp"

# Regenerate Resources/AppIcon.icns and assets/icon/icon.png from assets/icon.svg (needs Inkscape)
icons:
    scripts/make-icons.sh

# Format sources with swift-format (ships with Xcode)
fmt:
    xcrun swift-format format --in-place --recursive Sources Tests

clean:
    rm -rf .build build
