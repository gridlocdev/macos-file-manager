import Foundation
import Testing

@testable import FileManagerCore

@Suite struct ActionAvailabilityTests {
    struct State: ActionState {
        var selectedItems: [FileItem] = []
        var hasItems = true
        var canReadFolder = true
        var isTrashFolder = false
        var isAtRoot = false
        var hasOtherPane = false
        var tabCount = 1
        var hasClosedTabs = false
        var clipboardHasFiles = false
        var canUndo = false
        var canRedo = false
        var canGoBack = false
        var canGoForward = false
        var isSearchingSubfolders = false
        var hasSelection: Bool { !selectedItems.isEmpty }
    }

    let file = FileItem(url: URL(filePath: "/a/notes.txt"), name: "notes.txt", isFolder: false)
    let folder = FileItem(url: URL(filePath: "/a/Projects"), name: "Projects", isFolder: true)
    let zip = FileItem(url: URL(filePath: "/a/photos.zip"), name: "photos.zip", isFolder: false)

    @Test func selectionActionsNeedASelection() {
        let none = State()
        let some = State(selectedItems: [file])
        for action in [Action.open, .rename, .duplicate, .cut, .copy, .deleteImmediately, .quickLook] {
            #expect(!action.isAvailable(in: none))
            #expect(action.isAvailable(in: some))
        }
    }

    @Test func openContainingFolderOnlyForSubfolderResults() {
        #expect(!Action.openContainingFolder.isAvailable(in: State(selectedItems: [file])))
        #expect(!Action.openContainingFolder.isAvailable(in: State(isSearchingSubfolders: true)))
        #expect(Action.openContainingFolder.isAvailable(in: State(selectedItems: [file], isSearchingSubfolders: true)))
    }

    @Test func trashAndPutBackDependOnTheFolder() {
        var state = State(selectedItems: [file])
        #expect(Action.moveToTrash.isAvailable(in: state))
        #expect(!Action.putBack.isAvailable(in: state))
        state.isTrashFolder = true
        #expect(!Action.moveToTrash.isAvailable(in: state))
        #expect(!Action.compress.isAvailable(in: state))
        #expect(Action.putBack.isAvailable(in: state))
    }

    @Test func extractNeedsAnArchive() {
        #expect(!Action.extract.isAvailable(in: State(selectedItems: [file])))
        #expect(Action.extract.isAvailable(in: State(selectedItems: [file, zip])))
    }

    @Test func openInNewTabNeedsAFolder() {
        #expect(!Action.openInNewTab.isAvailable(in: State(selectedItems: [file])))
        #expect(Action.openInNewTab.isAvailable(in: State(selectedItems: [folder])))
    }

    @Test func tabs() {
        var state = State()
        #expect(!Action.nextTab.isAvailable(in: state))
        #expect(!Action.showTab9.isAvailable(in: state))
        #expect(Action.showTab1.isAvailable(in: state))
        #expect(!Action.showTab2.isAvailable(in: state))
        state.tabCount = 3
        #expect(Action.nextTab.isAvailable(in: state))
        #expect(Action.showTab9.isAvailable(in: state))
        #expect(Action.showTab3.isAvailable(in: state))
        #expect(!Action.showTab4.isAvailable(in: state))
    }

    @Test func pasteNeedsFilesAndAReadableFolder() {
        var state = State(clipboardHasFiles: true)
        #expect(Action.paste.isAvailable(in: state))
        state.canReadFolder = false
        #expect(!Action.paste.isAvailable(in: state))
        #expect(!Action.newFolder.isAvailable(in: state))
    }

    @Test func otherPaneAndNavigation() {
        #expect(!Action.copyToOtherPane.isAvailable(in: State(selectedItems: [file])))
        #expect(Action.copyToOtherPane.isAvailable(in: State(selectedItems: [file], hasOtherPane: true)))
        #expect(!Action.goUp.isAvailable(in: State(isAtRoot: true)))
        #expect(!Action.goBack.isAvailable(in: State()))
        #expect(Action.goBack.isAvailable(in: State(canGoBack: true)))
    }
}
