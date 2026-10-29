import Foundation

/// The app-wide objects a `BrowserModel` works with. Passed in rather than reached for, so the
/// model's dependencies are visible and tests can give it their own (stores kept in a scratch
/// folder, a private clipboard, settings in their own UserDefaults suite).
@MainActor
struct BrowserServices {
    var operations: FileOperations
    var windows: Windows
    var sidebar: SidebarStore
    var folderViews: FolderViewStore
    var clipboard: Clipboard
    var preferences: Preferences

    /// The ones every window shares.
    static var live: BrowserServices {
        BrowserServices(
            operations: .shared, windows: .shared, sidebar: .shared, folderViews: .shared, clipboard: .shared,
            preferences: .standard)
    }
}
