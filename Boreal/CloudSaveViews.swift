import SwiftUI

struct CloudSaveCard: View {
    @Environment(BorealStore.self) private var store
    let game: StoreLibraryGame

    @State private var windowsPath = ""
    @State private var automaticSync = true
    @State private var isSavingPath = false
    @State private var message: String?
    @State private var pendingDirection: CloudSaveSyncDirection?

    private var status: CloudSaveStatus {
        store.cloudSaveStatus(for: game)
    }

    private var linkedApplication: WindowsApplication? {
        store.linkedApplication(for: game)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label("Cloud Saves", systemImage: "icloud.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
                statusBadge
            }

            if case .unavailable(let reason) = status.state {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let setupMessage {
                Label(setupMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if case .failed(let reason) = status.state {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Last synchronization")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(status.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    }
                    HStack {
                        Text("Save files")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(status.local.fileCount) local · \(status.cloud.fileCount) cloud")
                    }
                    HStack {
                        Text("Cloud usage")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: status.cloud.totalBytes, countStyle: .file))
                    }
                    if status.lastUploadedCount > 0 || status.lastDownloadedCount > 0 || status.lastDeletedCount > 0 {
                        Text(lastTransferDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Save location")
                        .font(.callout.weight(.medium))
                    HStack(spacing: 8) {
                        TextField(#"e.g. C:\Users\boreal\Documents\Game\Saves"#, text: $windowsPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                        Button("Save") {
                            savePath()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSavingPath || windowsPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button("Use automatic detection", systemImage: "wand.and.stars") {
                        windowsPath = ""
                        savePath()
                    }
                    .buttonStyle(.link)
                    .disabled(isSavingPath)
                    if status.pathSource == nil {
                        Text("No save folder was detected. Enter the actual Windows folder used by this game; Boreal will not sync a guessed or empty folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let pathSource = status.pathSource {
                        Label(
                            pathSource == .detected ? "Detected automatically" : "Configured manually",
                            systemImage: pathSource == .detected ? "wand.and.stars" : "pencil"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let actualURL = status.resolvedURL {
                        Text(actualURL.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }

                Toggle("Automatic sync before launch and after exit", isOn: Binding(
                    get: { automaticSync },
                    set: { newValue in
                        automaticSync = newValue
                        Task {
                            do {
                                if let linkedApplication {
                                    try await store.setAutomaticCloudSaveSync(newValue, for: linkedApplication.id)
                                }
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        store.syncCloudSaves(for: game)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || status.state == .needsConfiguration)
                    Spacer()
                    if status.resolvedURL != nil {
                        Button("Open Save Folder", systemImage: "folder") {
                            store.openCloudSaveFolder(for: game)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if status.state != .conflict {
                    HStack(spacing: 8) {
                        Button("Download from Cloud", systemImage: "arrow.down.circle") {
                            pendingDirection = .useCloud
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy || status.state == .needsConfiguration)
                        Button("Upload to Cloud", systemImage: "arrow.up.circle") {
                            pendingDirection = .useLocal
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy || status.state == .needsConfiguration)
                    }
                }

                if status.state == .conflict {
                    conflictView
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
        .task(id: game.storeReference) {
            await loadConfiguration()
            store.refreshCloudSaveStatus(for: game)
        }
        .alert("Cloud Saves", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Replace one copy of the saves?",
            isPresented: Binding(
                get: { pendingDirection != nil },
                set: { if !$0 { pendingDirection = nil } }
            )
        ) {
            Button("Continue", role: .destructive) {
                guard let pendingDirection else { return }
                self.pendingDirection = nil
                store.syncCloudSaves(for: game, direction: pendingDirection)
            }
            Button("Cancel", role: .cancel) { pendingDirection = nil }
        } message: {
            Text("Boreal will create a backup before replacing the selected copy.")
        }
    }

    private var isBusy: Bool {
        switch status.state {
        case .checking, .syncing: true
        default: false
        }
    }

    private var setupMessage: String? {
        guard let application = linkedApplication else {
            return "Prepare the Windows game environment to enable GOG Cloud Saves."
        }
        guard let installation = store.installation(for: game) else {
            return "Install the Windows version of this game before configuring GOG Cloud Saves."
        }
        guard installation.platform == .windows else {
            return "GOG Cloud Saves require the Windows version of this game."
        }
        guard installation.state == .installed else {
            return "Finish preparing the Windows game environment before configuring GOG Cloud Saves."
        }
        guard let environmentPath = store.environment(id: application.environmentID)?.prefixPath,
              !environmentPath.isEmpty else {
            return "Prepare the Windows game environment to enable GOG Cloud Saves."
        }
        return nil
    }

    @ViewBuilder private var statusBadge: some View {
        if setupMessage != nil {
            Label("Setup required", systemImage: "wrench.and.screwdriver")
                .foregroundStyle(.orange)
        } else {
            switch status.state {
            case .synced:
                Label("Synced", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .syncing:
                Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.cyan)
            case .checking:
                Label("Checking…", systemImage: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            case .conflict:
                Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .needsConfiguration:
                Label("Path required", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.orange)
            case .failed:
                Label("Unavailable", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.orange)
            case .unavailable:
                Label("Unavailable", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastTransferDescription: String {
        var parts: [String] = []
        if status.lastUploadedCount > 0 { parts.append("\(status.lastUploadedCount) uploaded") }
        if status.lastDownloadedCount > 0 { parts.append("\(status.lastDownloadedCount) downloaded") }
        if status.lastDeletedCount > 0 { parts.append("\(status.lastDeletedCount) deleted") }
        return parts.joined(separator: " · ")
    }

    private var conflictView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Boreal needs your choice before replacing saves.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(alignment: .top, spacing: 22) {
                saveSummary("LOCAL", summary: status.local)
                saveSummary("GOG CLOUD", summary: status.cloud)
            }
            Text("A backup is always created before either copy is replaced.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Use Cloud") { pendingDirection = .useCloud }
                    .buttonStyle(.bordered)
                Button("Use Local") { pendingDirection = .useLocal }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func saveSummary(_ title: String, summary: CloudSaveSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(summary.fileCount) files")
            Text(ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let date = summary.latestModification {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadConfiguration() async {
        guard let linkedApplication else { return }
        let configuration = await store.advancedConfiguration(for: linkedApplication.id)
        windowsPath = configuration.cloudSaveWindowsPath ?? ""
        automaticSync = configuration.automaticCloudSaveSync
    }

    private func savePath() {
        guard let linkedApplication else { return }
        isSavingPath = true
        Task {
            defer { isSavingPath = false }
            do {
                try await store.updateCloudSavePath(for: linkedApplication.id, windowsPath: windowsPath)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
