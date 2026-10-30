import FileManagerCore
import SwiftUI

/// Rename with several items selected: new name, find and replace, case and numbers, with a
/// live preview. Rename stays disabled while any new name has a problem.
struct BatchRenameView: View {
    let request: BatchRenameRequest
    let model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var options = BatchRenameOptions()
    /// Names in each folder the items are in, read once.
    @State private var existing: [String: Set<String>] = [:]

    private var preview: BatchRename.Preview {
        BatchRename.preview(request.items, options: options) { existing[$0.path] ?? [] }
    }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(request.items.count) Items").font(.headline)
            Form {
                TextField("New name", text: $options.newName, prompt: Text("Keep each name"))
                TextField("Find", text: $options.find)
                TextField("Replace with", text: $options.replace)
                HStack {
                    Toggle("Match case", isOn: $options.matchCase).pointerCursor()
                    Toggle("Regular expression", isOn: $options.useRegex).pointerCursor()
                        .help("Find is a regular expression; use $1, $2… in Replace for its groups")
                }
                Picker("Case", selection: $options.caseChange) {
                    ForEach(BatchRenameOptions.CaseChange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pointerCursor()
                Picker("Numbers", selection: $options.numbering) {
                    ForEach(BatchRenameOptions.Numbering.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pointerCursor()
                if options.numbering != .none {
                    HStack {
                        TextField("Start at", value: $options.startNumber, format: .number)
                            .frame(width: 110)
                        Stepper("Digits: \(options.digits)", value: $options.digits, in: 1...6).pointerCursor()
                        TextField("Separator", text: $options.separator)
                            .frame(width: 120)
                    }
                }
                Toggle("Change extensions too", isOn: $options.includeExtension).pointerCursor()
            }
            if let error = preview.patternError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Table(preview.entries.indices.map { IndexedEntry(index: $0, entry: preview.entries[$0]) }) {
                TableColumn("Name") { Text($0.entry.name).lineLimit(1).truncationMode(.middle) }
                TableColumn("New Name") { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.entry.newName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(row.entry.problem != nil ? .red : row.entry.isChanged ? .primary : .secondary)
                        if let problem = row.entry.problem {
                            Text(problem).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            .frame(minHeight: 180)
            HStack {
                let changed = preview.entries.count(where: \.isChanged)
                Text(changed == 1 ? "1 name changes" : "\(changed) names change").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .pointerCursor()
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    model.commitBatchRename(preview.entries)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!preview.canRename)
                .pointerCursor()
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
        .onAppear(perform: readFolders)
    }

    private func readFolders() {
        let folders = Set(request.items.map { $0.url.deletingLastPathComponent().path })
        for folder in folders {
            existing[folder] = Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
        }
    }

    private struct IndexedEntry: Identifiable {
        let index: Int
        let entry: BatchRename.Entry
        var id: Int { index }
    }
}
