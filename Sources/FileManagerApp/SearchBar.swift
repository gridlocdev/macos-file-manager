import FileManagerCore
import SwiftUI

/// The find bar above the list (Cmd+F). Typing filters the folder as you type; Subfolders
/// searches everything below it. Esc closes it; Down arrow or Return goes to the results.
struct SearchBar: View {
    @Bindable var model: BrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in “\(model.title)”", text: $model.criteria.text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.focusResults() }
                .onExitCommand { model.endSearch() }
                .onKeyPress(.downArrow) {
                    model.focusResults()
                    return .handled
                }
                .help("Part of a name, or a pattern such as *.jpg. Esc closes.")
                .accessibilityLabel("Find")
            Picker("Search in", selection: $model.searchScope) {
                Text("This Folder").tag(BrowserModel.SearchScope.folder)
                Text("Subfolders").tag(BrowserModel.SearchScope.subfolders)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Search only this folder, or every folder inside it too")
            filters
            Button("Close", systemImage: "xmark.circle.fill") { model.endSearch() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close Find (Esc)")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.bar)
        .onAppear { focused = true }
        .onChange(of: model.searchFocusRequest) {
            focused = true
            // Cmd+F again selects what's typed, ready to type over it.
            DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
        }
    }

    private var filters: some View {
        let active = [model.criteria.kind != .any, model.criteria.date != .any, model.criteria.size != .any]
            .filter { $0 }.count
        return Menu {
            Picker("Kind", selection: $model.criteria.kind) {
                ForEach(SearchCriteria.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Date Modified", selection: $model.criteria.date) {
                ForEach(SearchCriteria.DateRange.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Size", selection: $model.criteria.size) {
                ForEach(SearchCriteria.SizeRange.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if active > 0 {
                Divider()
                Button("Clear Filters") {
                    model.criteria.kind = .any
                    model.criteria.date = .any
                    model.criteria.size = .any
                }
            }
        } label: {
            Label(active > 0 ? "Filters (\(active))" : "Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Only show items of a kind, date or size")
    }
}
