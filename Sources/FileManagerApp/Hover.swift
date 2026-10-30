import AppKit
import SwiftUI

extension View {
    /// Calls `changed` when the mouse enters and leaves. Unlike `.onHover`, this works inside a
    /// toolbar item, where SwiftUI's hover never fires; it uses an AppKit tracking area.
    func onMouseOver(pointer: Bool = true, _ changed: @escaping (Bool) -> Void) -> some View {
        background(HoverTracker(pointer: pointer, changed: changed))
    }

    /// The pointing-hand cursor over anything that can be clicked (buttons, menus, sidebar rows,
    /// breadcrumbs), app-wide.
    func pointerCursor() -> some View {
        pointerStyle(.link).background(HoverTracker(pointer: true, changed: nil))
    }
}

/// A sidebar row's hover: a muted version of the selection highlight (the selected row keeps
/// its own, brighter one), and the pointing hand.
struct SidebarHover: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onMouseOver { hovering = $0 }
            // Out to where the selection highlight is drawn (listRowBackground only shows on
            // some rows of a sidebar list).
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
                    .padding(.leading, -15)
                    .padding(.trailing, -6)
                    .padding(.vertical, -4))
    }
}

private struct HoverTracker: NSViewRepresentable {
    let pointer: Bool
    let changed: ((Bool) -> Void)?

    func makeNSView(context: Context) -> TrackingView { TrackingView() }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.pointer = pointer
        view.changed = changed
    }

    /// Only a real mouse-entered turns hover on. A sidebar row redrawn or reused under the mouse
    /// can lose its exited event and stay lit, so any hover change re-checks every view that's
    /// lit and turns off those the mouse isn't over (the check never turns one on: just after
    /// layout a view's frame can be stale, and every breadcrumb lit up).
    final class TrackingView: NSView {
        var pointer = true
        var changed: ((Bool) -> Void)?
        private var inside = false
        private static var hovered: [ObjectIdentifier: () -> Void] = [:]

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self))
            recheck()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            recheck()
        }

        override func mouseEntered(with event: NSEvent) {
            if pointer { NSCursor.pointingHand.set() }
            Self.recheckAll()
            set(true)
        }

        override func mouseExited(with event: NSEvent) {
            if pointer { NSCursor.arrow.set() }
            set(false)
            Self.recheckAll()
        }

        private func recheck() {
            guard inside else { return }
            guard let window, !isHiddenOrHasHiddenAncestor,
                visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
            else { return set(false) }
        }

        private static func recheckAll() {
            for recheck in Array(hovered.values) { recheck() }
        }

        private func set(_ now: Bool) {
            if now { Self.hovered[ObjectIdentifier(self)] = { [weak self] in self?.recheck() } }
            else { Self.hovered[ObjectIdentifier(self)] = nil }
            guard now != inside else { return }
            inside = now
            changed?(now)
        }

        deinit {
            // The view goes on the main thread; drop its entry so the table doesn't grow.
            let id = ObjectIdentifier(self)
            MainActor.assumeIsolated { Self.hovered[id] = nil }
        }

        override func cursorUpdate(with event: NSEvent) {
            if pointer { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
        }

        // Clicks go to the control above.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    /// Dragging this sidebar row shows the row, faded, as Finder does (SwiftUI's list draws its
    /// own lifted preview instead).
    func fadedDragImage(title: String, symbol: String) -> some View {
        background(FadedDragImage(title: title, symbol: symbol))
    }
}

/// Patches the class of the list the row is in, once: after the list starts a drag, each
/// dragged row's image is replaced by a faded drawing of its icon and title. The row can't be
/// snapshotted: the sidebar draws text and icons with vibrancy, which comes out black.
private struct FadedDragImage: NSViewRepresentable {
    let title: String
    let symbol: String

    func makeNSView(context: Context) -> Patcher { Patcher() }

    func updateNSView(_ view: Patcher, context: Context) {
        view.title = title
        view.symbol = symbol
    }

    final class Patcher: NSView {
        var title = ""
        var symbol = ""
        private static var patched: Set<ObjectIdentifier> = []
        private static let selector = #selector(NSTableView.draggingSession(_:willBeginAt:))

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view = superview
            while let current = view, !(current is NSTableView) { view = current.superview }
            guard let table = view as? NSTableView else { return }
            let cls: AnyClass = type(of: table)
            guard Self.patched.insert(ObjectIdentifier(cls)).inserted,
                let method = class_getInstanceMethod(cls, Self.selector)
            else { return }
            typealias Original = @convention(c) (NSTableView, Selector, NSDraggingSession, NSPoint) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (NSTableView, NSDraggingSession, NSPoint) -> Void = { table, session, point in
                original(table, Self.selector, session, point)
                MainActor.assumeIsolated { Self.fade(session, in: table, at: point) }
            }
            class_replaceMethod(cls, Self.selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
        }

        /// The row as the sidebar shows it: accent-coloured icon, title in the label colour.
        private func image(appearance: NSAppearance, scale: CGFloat) -> NSImage? {
            // Sized as the sidebar draws its rows (larger icons than a plain Label).
            let row = HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 19)
                Text(title).font(.system(size: 13)).foregroundStyle(.primary)
            }
            .environment(\.colorScheme, appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
            .opacity(0.65)
            let renderer = ImageRenderer(content: row)
            renderer.scale = scale
            return renderer.nsImage
        }

        private static func patcher(in view: NSView) -> Patcher? {
            if let patcher = view as? Patcher { return patcher }
            for sub in view.subviews { if let found = patcher(in: sub) { return found } }
            return nil
        }

        private static func fade(_ session: NSDraggingSession, in table: NSTableView, at screenPoint: NSPoint) {
            guard let window = table.window else { return }
            let point = table.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
            let row = table.row(at: point)
            // Rows dragged: the one under the mouse, or the selection when it's among them.
            let rows = table.selectedRowIndexes.contains(row) ? Array(table.selectedRowIndexes) : [row]
            var images = rows.compactMap { row -> (NSRect, NSImage)? in
                guard row >= 0, let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false),
                    let patcher = patcher(in: cell),
                    let image = patcher.image(appearance: table.effectiveAppearance, scale: window.backingScaleFactor)
                else { return nil }
                // Where the row's label is drawn, centred on it vertically.
                let label = table.convert(patcher.bounds, from: patcher)
                let frame = NSRect(
                    x: label.minX, y: label.midY - image.size.height / 2,
                    width: image.size.width, height: image.size.height)
                return (frame, image)
            }.makeIterator()
            session.enumerateDraggingItems(options: [], for: table, classes: [NSPasteboardItem.self], searchOptions: [:]) {
                item, _, stop in
                guard let (frame, image) = images.next() else { return stop.pointee = true }
                item.setDraggingFrame(frame, contents: image)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
