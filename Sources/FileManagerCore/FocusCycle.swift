/// F6 / Shift+F6, like Explorer: file list → address bar → sidebar → file list. With a split
/// view the right-hand list comes between the left one and the address bar.
public enum FocusCycle {
    public enum Area: Equatable, Sendable { case leftList, rightList, addressBar, sidebar }

    /// Where the focus goes from `current` (nil: somewhere else, such as the find bar).
    public static func next(from current: Area?, forward: Bool, isSplit: Bool) -> Area {
        switch (forward, current) {
        case (true, .leftList): isSplit ? .rightList : .addressBar
        case (true, .rightList): .addressBar
        case (true, .addressBar): .sidebar
        case (true, _): .leftList
        case (false, .rightList): .leftList
        case (false, .leftList): .sidebar
        case (false, .addressBar): isSplit ? .rightList : .leftList
        case (false, _): .addressBar
        }
    }
}
