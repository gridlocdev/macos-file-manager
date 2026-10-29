# File Manager — SwiftUI app built with SwiftPM + Xcode's toolchain (no .xcodeproj).

app := "build/File Manager.app"

default:
    @just --list

# Compile (debug) with Xcode's Swift toolchain
build:
    xcrun swift build

# Run the unit tests (keymap, history, paths, sorting, docs)
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
    pkill -x FileManagerApp || true
    rm -f build/snapshot.log
    open -W -n --stdout "$PWD/build/snapshot.log" --stderr "$PWD/build/snapshot.log" --env FILEMANAGER_SNAPSHOT="$PWD/{{out}}" --env FILEMANAGER_SNAPSHOT_FOLDER="$PWD/build/snapshot-demo" --env FILEMANAGER_SNAPSHOT_KEYS="{{keys}}" "{{app}}"
    cat build/snapshot.log

# Regenerate Resources/AppIcon.icns from assets/icon.svg (needs Inkscape)
icons:
    scripts/make-icons.sh

# Format sources with swift-format (ships with Xcode)
fmt:
    xcrun swift-format format --in-place --recursive Sources Tests

clean:
    rm -rf .build build
