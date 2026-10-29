import FileManagerCore
import QuickLookUI
import SwiftUI

/// The docked preview on the right (Opt+P): a Quick Look preview of the selected item with its
/// details under it. With nothing or several items selected it sums up instead.
struct PreviewPane: View {
    var model: BrowserModel

    var body: some View {
        let selected = model.items.filter { model.selection.contains($0.url) }
        VStack(spacing: 0) {
            if selected.count == 1, let item = selected.first {
                QuickLookPreview(url: item.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                details(item)
            } else {
                summary(selected)
            }
        }
        .frame(minWidth: 200, idealWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview")
    }

    private func details(_ item: FileItem) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text(item.name).font(.headline).lineLimit(2).truncationMode(.middle).gridCellColumns(2)
            }
            row("Kind", item.kind)
            if !item.isFolder { row("Size", FileFormat.size(item.size)) }
            row("Modified", FileFormat.date(item.modified))
            row("Created", FileFormat.date(item.created))
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).lineLimit(1).truncationMode(.middle)
        }
    }

    private func summary(_ selected: [FileItem]) -> some View {
        VStack(spacing: 6) {
            Image(systemName: selected.isEmpty ? "eye.slash" : "square.stack")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            if selected.isEmpty {
                Text("No selection").foregroundStyle(.secondary)
                Text("Select a file to preview it.").font(.callout).foregroundStyle(.tertiary)
            } else {
                Text("\(selected.count) items selected").foregroundStyle(.secondary)
                let size = selected.filter { !$0.isFolder }.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
                if size > 0 { Text(FileFormat.size(size)).font(.callout).foregroundStyle(.tertiary) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Quick Look's own preview view, the same one the Space-bar panel uses.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.shouldCloseWithWindow = false
        view.autostarts = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
