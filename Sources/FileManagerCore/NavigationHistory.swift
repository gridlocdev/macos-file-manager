import Foundation

/// Back/Forward for one pane, like a browser's. A page can carry what was showing when it was
/// left (`Saved`: an open search, the selection), handed back on returning to it.
public struct NavigationHistory<Saved: Sendable>: Sendable {
    private struct Page: Sendable {
        var url: URL
        var saved: Saved?
    }

    public private(set) var current: URL
    /// What was saved with the current page when it was last left; nil for a new page.
    public private(set) var saved: Saved?
    private var backPages: [Page] = []
    private var forwardPages: [Page] = []

    public init(start: URL) { current = start }

    public var back: [URL] { backPages.map(\.url) }
    public var forward: [URL] { forwardPages.map(\.url) }
    public var canGoBack: Bool { !backPages.isEmpty }
    public var canGoForward: Bool { !forwardPages.isEmpty }

    /// A new page: pushes the current one (with `leaving`) onto Back and clears Forward. The same
    /// folder again counts only when there's something to come back to (a search being left).
    public mutating func visit(_ url: URL, leaving: Saved? = nil) {
        guard url != current || leaving != nil else { return }
        backPages.append(Page(url: current, saved: leaving))
        forwardPages.removeAll()
        current = url
        saved = nil
    }

    public mutating func goBack(leaving: Saved? = nil) -> URL? {
        guard let previous = backPages.popLast() else { return nil }
        forwardPages.append(Page(url: current, saved: leaving))
        current = previous.url
        saved = previous.saved
        return previous.url
    }

    public mutating func goForward(leaving: Saved? = nil) -> URL? {
        guard let next = forwardPages.popLast() else { return nil }
        backPages.append(Page(url: current, saved: leaving))
        current = next.url
        saved = next.saved
        return next.url
    }
}
