import SwiftUI

/// File Operations window: running copies, moves and trashes with progress and Cancel.
/// Opens when a job takes more than a moment and closes when the last one finishes.
struct OperationsWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    private var ops: FileOperations { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if ops.jobs.isEmpty {
                Text("No file operations running.").foregroundStyle(.secondary)
            }
            ForEach(ops.jobs) { job in
                JobRow(job: job)
            }
        }
        .padding(16)
        .frame(width: 440, alignment: .topLeading)
        .onChange(of: ops.jobs.isEmpty) {
            if ops.jobs.isEmpty { dismissWindow(id: OperationsWindow.id) }
        }
    }

    static let id = "operations"
}

private struct JobRow: View {
    let job: FileJob

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title).lineLimit(1).truncationMode(.middle)
                ProgressView(value: job.fraction)
                Text(job.currentName.isEmpty ? "Starting…" : job.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Cancel", systemImage: "xmark.circle.fill") { job.cancel() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Stop. What's already done stays done, and Undo reverses it.")
                .pointerCursor()
        }
    }
}
