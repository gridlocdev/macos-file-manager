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
