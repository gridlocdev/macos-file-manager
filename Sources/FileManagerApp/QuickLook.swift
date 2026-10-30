import AppKit
import QuickLookUI

/// The details list and the icon view. Return renames and Delete trashes only while one of
/// these has the keyboard focus (see `KeyMonitor`).
@MainActor protocol FileBrowsingView: NSView {
    var quickLook: QuickLookSource { get }
}

/// Quick Look for a file view: the panel shows the view's selection, Up/Down move through the
/// view as in Finder, and Space closes it. The view passes the panel's control calls here.
@MainActor final class QuickLookSource: NSObject {
    var urls: () -> [URL] = { [] }
    /// Where the item is on screen, so the preview zooms out of its icon.
    var frameOnScreen: (URL) -> NSRect? = { _ in nil }
    weak var view: NSView?

    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func end(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func toggle() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            view?.window?.makeFirstResponder(view)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Keeps an open panel on the current selection.
    func selectionChanged() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible,
            panel.dataSource === self
        else { return }
        panel.reloadData()
    }
}

extension QuickLookSource: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls().count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        // The selection can shrink while the panel is open (a refresh, Trash).
        let urls = urls()
        return urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    /// Arrow keys in the panel move through the view, as in Finder; Space closes it. Everything
    /// else (Esc, paging within a multi-page preview) is the panel's.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        switch event.keyCode {
        case 123, 124, 125, 126:
            // Left/Right only matter in the icon view; the list ignores them.
            guard event.keyCode >= 125 || view is NSCollectionView else { return false }
            view?.keyDown(with: event)
            return true
        case 49:
            panel.orderOut(nil)
            return true
        default:
            return false
        }
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let url = item.previewItemURL ?? nil else { return .zero }
        return frameOnScreen(url.normalized) ?? .zero
    }
}
