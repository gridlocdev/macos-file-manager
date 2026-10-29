// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Info.plist is embedded in the executable too, so `swift run` and the VS Code debugger
// show "File Manager" in the menu bar without the .app bundle.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "FileManager",
    platforms: [.macOS("27.0")],
    targets: [
        // Pure logic (keymap, history, paths, sorting), no AppKit, so it can be unit tested.
        .target(name: "FileManagerCore", path: "Sources/FileManagerCore"),
        .executableTarget(
            name: "FileManagerApp",
            dependencies: ["FileManagerCore"],
            path: "Sources/FileManagerApp",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist", "-Xlinker", "\(root)/Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "FileManagerCoreTests",
            dependencies: ["FileManagerCore"],
            path: "Tests/FileManagerCoreTests"
        ),
        // The app's models (BrowserModel, FileOperations) with scratch folders and stores.
        .testTarget(
            name: "FileManagerAppTests",
            dependencies: ["FileManagerApp"],
            path: "Tests/FileManagerAppTests"
        ),
    ]
)
