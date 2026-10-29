import FileManagerCore
import SwiftUI

/// One window: sidebar, toolbar with back/forward/up and the address bar, file list, status bar.
struct BrowserWindow: View {
    @State private var model = BrowserModel()
    @AppStorage(SettingsKey.foldersFirst) private var foldersFirst = true

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            VStack(spacing: 0) {
                FileListView(model: model)
                    .overlay { emptyOrError }
                StatusBar(model: model)
            }
        }
        .navigationTitle(model.title)
        // The address bar shows where you are; the title would only crowd it out. The title is
        // still used by the Window menu.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") { model.perform(.goBack) }
                    .disabled(!model.canPerform(.goBack))
                    .help("Back (Opt+Left)")
                Button("Forward", systemImage: "chevron.right") { model.perform(.goForward) }
                    .disabled(!model.canPerform(.goForward))
                    .help("Forward (Opt+Right)")
                Button("Up", systemImage: "arrow.up") { model.perform(.goUp) }
                    .disabled(!model.canPerform(.goUp))
                    .help("Enclosing folder (Backspace)")
            }
            ToolbarItem(placement: .principal) {
                AddressBar(model: model)
            }
        }
        .background(KeyMonitor(model: model))
        .frame(minWidth: 640, minHeight: 360)
        .onAppear {
            model.sort.foldersFirst = foldersFirst
            model.focusList()
        }
        .onChange(of: foldersFirst) { model.sort.foldersFirst = foldersFirst }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugNavigate)) { note in
            if let url = note.object as? URL { model.navigate(to: url) }
        }
        #endif
    }

    @ViewBuilder private var emptyOrError: some View {
        if let message = model.errorMessage {
            ContentUnavailableView("Can't Open Folder", systemImage: "lock", description: Text(message))
        } else if model.items.isEmpty && !model.isLoading {
            Text("This folder is empty").foregroundStyle(.secondary)
        }
    }
}

struct AddressBar: View {
    @Bindable var model: BrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Path", text: $model.addressText)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .frame(minWidth: 280, idealWidth: 520, maxWidth: .infinity)
            .focused($focused)
            .onSubmit { model.submitAddress() }
            .onExitCommand { model.cancelAddressEdit() }
            .onKeyPress(.tab) {
                model.completeAddress()
                return .handled
            }
            .onChange(of: model.addressFocusRequest) { focused = true }
            .onChange(of: focused) {
                if !focused { model.addressText = PathInput.display(model.url, home: model.home) }
            }
            .help("Type a path and press Return. Tab completes folder names. (Cmd+L)")
            .accessibilityLabel("Address")
    }
}

struct StatusBar: View {
    var model: BrowserModel

    var body: some View {
        HStack(spacing: 8) {
            Text(summary)
            if model.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            if model.showHiddenFiles { Text("Showing hidden files") }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    private var summary: String {
        let count = model.items.count
        var text = count == 1 ? "1 item" : "\(count) items"
        if !model.selection.isEmpty { text += ", \(model.selection.count) selected" }
        return text
    }
}
