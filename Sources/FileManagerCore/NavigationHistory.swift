import Foundation

/// Back/forward stacks for one browser tab.
public struct NavigationHistory: Sendable {
    public private(set) var current: URL
    public private(set) var back: [URL] = []
    public private(set) var forward: [URL] = []

    public init(start: URL) { current = start }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// A new folder: pushes the current one onto Back and clears Forward.
    public mutating func visit(_ url: URL) {
        guard url != current else { return }
        back.append(current)
        forward.removeAll()
        current = url
    }

    public mutating func goBack() -> URL? {
        guard let previous = back.popLast() else { return nil }
        forward.append(current)
        current = previous
        return previous
    }

    public mutating func goForward() -> URL? {
        guard let next = forward.popLast() else { return nil }
        back.append(current)
        current = next
        return next
    }
}
