import AppKit
import SwiftUI

struct SidebarItem: Identifiable, Hashable {
    var url: URL
    var title: String
    var symbol: String
    var id: URL { url }
}

/// Favorites and mounted volumes. Selecting one opens it.
struct SidebarView: View {
    var model: BrowserModel
    @State private var volumes: [SidebarItem] = SidebarView.mountedVolumes()

    var body: some View {
        List(selection: selectionBinding) {
            Section("Favorites") {
                ForEach(favorites) { row($0) }
            }
            Section("Locations") {
                ForEach(volumes) { row($0) }
            }
        }
        .listStyle(.sidebar)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = Self.mountedVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = Self.mountedVolumes()
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol).tag(item.url)
    }

    /// Highlights the item for the current folder; picking one navigates.
    private var selectionBinding: Binding<URL?> {
        Binding(
            get: {
                let current = model.url.standardizedFileURL
                return (favorites + volumes).first { $0.url.standardizedFileURL == current }?.url
            },
            set: { url in
                guard let url else { return }
                model.navigate(to: url)
                model.focusList()
            }
        )
    }

    private var favorites: [SidebarItem] {
        let home = model.home
        var items = [
            SidebarItem(url: home, title: FileManager.default.displayName(atPath: home.path), symbol: "house"),
            SidebarItem(url: home.appendingPathComponent("Desktop"), title: "Desktop", symbol: "menubar.dock.rectangle"),
            SidebarItem(url: home.appendingPathComponent("Documents"), title: "Documents", symbol: "doc"),
            SidebarItem(url: home.appendingPathComponent("Downloads"), title: "Downloads", symbol: "arrow.down.circle"),
            SidebarItem(url: URL(fileURLWithPath: "/Applications"), title: "Applications", symbol: "square.grid.3x3"),
        ]
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloud.path) {
            items.append(SidebarItem(url: iCloud, title: "iCloud Drive", symbol: "icloud"))
        }
        return items
    }

    static func mountedVolumes() -> [SidebarItem] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsInternalKey, .volumeIsRemovableKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let symbol =
                url.path == "/" || values?.volumeIsInternal == true ? "internaldrive"
                : values?.volumeIsRemovable == true ? "externaldrive" : "server.rack"
            return SidebarItem(
                url: url, title: values?.volumeLocalizedName ?? url.lastPathComponent, symbol: symbol)
        }
    }
}
