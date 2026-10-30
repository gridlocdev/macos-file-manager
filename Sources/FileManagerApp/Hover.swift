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

    final class TrackingView: NSView {
        var pointer = true
        var changed: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self))
        }

        override func mouseEntered(with event: NSEvent) {
            if pointer { NSCursor.pointingHand.set() }
            changed?(true)
        }

        override func mouseExited(with event: NSEvent) {
            if pointer { NSCursor.arrow.set() }
            changed?(false)
        }

        override func cursorUpdate(with event: NSEvent) {
            if pointer { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
        }

        // Clicks go to the control above.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
