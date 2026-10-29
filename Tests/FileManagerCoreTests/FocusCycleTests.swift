import Testing

@testable import FileManagerCore

@Suite struct FocusCycleTests {
    func walk(from start: FocusCycle.Area, forward: Bool, isSplit: Bool) -> [FocusCycle.Area] {
        var area = start
        var seen: [FocusCycle.Area] = []
        for _ in 0..<4 {
            area = FocusCycle.next(from: area, forward: forward, isSplit: isSplit)
            seen.append(area)
        }
        return seen
    }

    @Test func forwardGoesListAddressSidebar() {
        #expect(walk(from: .leftList, forward: true, isSplit: false) == [.addressBar, .sidebar, .leftList, .addressBar])
    }

    @Test func forwardWithSplitVisitsRightList() {
        #expect(walk(from: .leftList, forward: true, isSplit: true) == [.rightList, .addressBar, .sidebar, .leftList])
    }

    @Test func backwardReversesForward() {
        #expect(walk(from: .leftList, forward: false, isSplit: true) == [.sidebar, .addressBar, .rightList, .leftList])
        #expect(walk(from: .leftList, forward: false, isSplit: false) == [.sidebar, .addressBar, .leftList, .sidebar])
    }

    @Test func elsewhereStartsAtTheEnds() {
        #expect(FocusCycle.next(from: nil, forward: true, isSplit: true) == .leftList)
        #expect(FocusCycle.next(from: nil, forward: false, isSplit: true) == .addressBar)
    }
}
