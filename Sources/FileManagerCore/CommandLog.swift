/// One-shot requests from a model to its views ("focus the list", "start renaming this"), kept
/// as a short numbered log. Each view remembers the last number it handled and takes what came
/// after, so two requests in a row both arrive, and a view that appears later doesn't replay
/// old ones.
public struct CommandLog<Command: Sendable>: Sendable {
    /// The number of the newest command; 0 before any.
    public private(set) var last = 0
    private var entries: [(number: Int, command: Command)] = []
    /// Older commands are forgotten past this many.
    public let capacity: Int

    public init(capacity: Int = 64) { self.capacity = capacity }

    public mutating func send(_ command: Command) {
        last += 1
        entries.append((last, command))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    /// Commands newer than `number`, oldest first.
    public func commands(after number: Int) -> [Command] {
        entries.filter { $0.number > number }.map(\.command)
    }
}
