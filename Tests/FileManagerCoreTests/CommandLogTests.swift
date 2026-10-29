import Testing

@testable import FileManagerCore

@Suite struct CommandLogTests {
    @Test func newerCommandsInOrder() {
        var log = CommandLog<String>()
        #expect(log.last == 0)
        log.send("a")
        let seen = log.last
        log.send("b")
        log.send("c")
        #expect(log.commands(after: seen) == ["b", "c"])
        #expect(log.commands(after: log.last).isEmpty)
        #expect(log.commands(after: 0) == ["a", "b", "c"])
    }

    @Test func forgetsPastCapacity() {
        var log = CommandLog<Int>(capacity: 2)
        for n in 1...5 { log.send(n) }
        #expect(log.last == 5)
        #expect(log.commands(after: 0) == [4, 5])
    }
}
