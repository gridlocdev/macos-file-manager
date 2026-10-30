import AppKit
import FileManagerCore
import NetFS
import SwiftUI

/// Connect to Server (Cmd+K): mounts an SMB, NFS or WebDAV share with macOS's own sign-in
/// (it asks for a name and password and can keep them in the keychain), then shows it in the
/// pane that asked.
struct ConnectToServerView: View {
    let model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.recentServers) private var recentText = ""
    @State private var address = ""
    @State private var problem: String?
    @State private var connecting = false
    @State private var connection: Task<Void, Never>?

    private var recent: [String] { recentText.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Server").font(.headline)
            TextField("Server address", text: $address, prompt: Text("smb://nas.local/share"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)
                .disabled(connecting)
            Text(verbatim: #"SMB, NFS and WebDAV (https://) servers. A Windows path like \\server\share works too."#)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !recent.isEmpty {
                Text("Recent Servers").font(.subheadline).foregroundStyle(.secondary)
                List(recent, id: \.self) { server in
                    Text(server)
                        .contentShape(Rectangle())
                        .onTapGesture { address = server }
                        .onTapGesture(count: 2) {
                            address = server
                            connect()
                        }
                }
                .frame(height: 120)
                .disabled(connecting)
            }
            HStack {
                if connecting {
                    ProgressView().controlSize(.small)
                    Text("Connecting…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    // Stop the mount too, or the pane would still jump to the share later.
                    connection?.cancel()
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(connecting || address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onDisappear { connection?.cancel() }
    }

    private func connect() {
        switch ServerAddress.parse(address) {
        case .failure(let failure):
            problem = failure.message
        case .success(let url):
            guard !connecting else { return }
            problem = nil
            connecting = true
            connection = Task {
                let result = await ServerMount.mount(url)
                connecting = false
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let folder):
                    recentText = ServerAddress.remember(address.trimmingCharacters(in: .whitespaces), in: recent)
                        .joined(separator: "\n")
                    dismiss()
                    model.navigate(to: folder)
                    model.focusList()
                case .failure(let error):
                    problem = error.localizedDescription
                }
            }
        }
    }
}

enum ServerMount {
    /// Mounts the share (or finds it already mounted) and returns its folder. Cancelling the
    /// task cancels the mount.
    @MainActor static func mount(_ url: URL) async -> Result<URL, Error> {
        if let mounted = alreadyMounted(url) { return .success(mounted) }
        let pending = PendingMount()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                start(url, pending: pending, continuation)
            }
        } onCancel: {
            Task { @MainActor in pending.cancel() }
        }
    }

    /// The mount request, so Cancel can stop it.
    @MainActor private final class PendingMount {
        var request: AsyncRequestID?
        var cancelled = false

        func cancel() {
            cancelled = true
            if let request { NetFSMountURLCancel(request) }
        }
    }

    @MainActor private static func start(
        _ url: URL, pending: PendingMount, _ continuation: CheckedContinuation<Result<URL, Error>, Never>
    ) {
        guard !pending.cancelled else {
            return continuation.resume(returning: .failure(CocoaError(.userCancelled)))
        }
        // Let macOS ask for the name and password (and offer the keychain).
        let openOptions = NSMutableDictionary()
        openOptions[kNAUIOptionKey] = kNAUIOptionAllowUI
        var request: AsyncRequestID?
        let status = NetFSMountURLAsync(
            url as CFURL, nil, nil, nil, openOptions as CFMutableDictionary, nil, &request, .main
        ) { status, _, mountpoints in
            let points = (mountpoints as? [String]) ?? []
            if status == 0, let first = points.first {
                continuation.resume(returning: .success(URL(filePath: first)))
            } else if status == EEXIST, let mounted = alreadyMounted(url) {
                continuation.resume(returning: .success(mounted))
            } else {
                continuation.resume(returning: .failure(error(status)))
            }
        }
        if status != 0 {
            continuation.resume(returning: .failure(error(status)))
        } else {
            pending.request = request
        }
    }

    /// A share that's mounted already (from Finder, or earlier) opens without asking again.
    private static func alreadyMounted(_ url: URL) -> URL? {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeURLForRemountingKey], options: [.skipHiddenVolumes]) ?? []
        return volumes.first { volume in
            guard let remount = (try? volume.resourceValues(forKeys: [.volumeURLForRemountingKey]))?.volumeURLForRemounting
            else { return false }
            return remount.host()?.lowercased() == url.host()?.lowercased()
                && remount.path.lowercased() == url.path.lowercased()
        }
    }

    private static func error(_ status: Int32) -> Error {
        switch status {
        case ECANCELED, Int32(userCanceledErr): return CocoaError(.userCancelled)
        case ENOENT, EHOSTUNREACH, ETIMEDOUT:
            return NSError(domain: NSPOSIXErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Can't reach the server. Check the address and that you're on its network.",
            ])
        case EAUTH, EACCES, EPERM:
            return NSError(domain: NSPOSIXErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "The server didn't accept the name or password.",
            ])
        default:
            return NSError(domain: NSPOSIXErrorDomain, code: Int(status))
        }
    }
}
