import AppKit
import Observation

/// Files on the system clipboard, so copy and paste work with Finder and other apps. Cut is
/// remembered here (the system clipboard has no "cut" for files): pasting after a cut moves.
@MainActor @Observable
final class Clipboard {
    static let shared = Clipboard()

    /// Items cut in this app and not yet pasted; shown dimmed.
    private(set) var cutURLs: Set<URL> = []
    private var cutChangeCount = -1
    private let pasteboard: NSPasteboard

    /// `pasteboard`: the system clipboard, or a private one in tests.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        // Anything copied elsewhere replaces a pending cut.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forgetStaleCut() }
        }
    }

    func copy(_ urls: [URL]) {
        write(urls)
        cutURLs = []
    }

    func cut(_ urls: [URL]) {
        write(urls)
        cutURLs = Set(urls.map(\.normalized))
        cutChangeCount = pasteboard.changeCount
    }

    func copyText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        cutURLs = []
    }

    /// File URLs on the clipboard, from this app or any other.
    var fileURLs: [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    var hasFiles: Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// True if the files on the clipboard were cut here, so pasting should move them.
    var isCut: Bool {
        forgetStaleCut()
        return !cutURLs.isEmpty
    }

    /// After a cut is pasted the items have moved; empty the clipboard so pasting again
    /// doesn't try to move them a second time (Explorer does the same). Items that didn't move
    /// (an error, Stop, Skip) stay cut, to paste again.
    func finishCut(leaving remaining: [URL] = []) {
        if remaining.isEmpty {
            cutURLs = []
            pasteboard.clearContents()
        } else {
            cut(remaining)
        }
    }

    func forgetStaleCut() {
        if !cutURLs.isEmpty, pasteboard.changeCount != cutChangeCount { cutURLs = [] }
    }

    private func write(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }
}
