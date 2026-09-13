import AppKit
import SwiftUI

struct CloudSaveCard: View {
    @Environment(BorealStore.self) private var store
    let game: StoreLibraryGame

    @State private var windowsPath = ""
    @State private var automaticSync = true
    @State private var isSavingPath = false
    @State private var message: String?
    @State private var pendingDirection: CloudSaveSyncDirection?
    @State private var isEditingPath = false
    @State private var showsAdvanced = false
    @State private var showsGOGAuthorizationCode = false
    @State private var gogAuthorizationCode = ""

    private var status: CloudSaveStatus {
        store.cloudSaveStatus(for: game)
    }

    private var linkedApplication: WindowsApplication? {
        store.linkedApplication(for: game)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Cloud Saves", systemImage: "icloud.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
                statusBadge
            }

            cloudSaveContent
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
        .task(id: game.storeReference) {
            await loadConfiguration()
            store.refreshGOGConnection()
            store.refreshCloudSaveStatus(for: game)
        }
        .onChange(of: store.gogConnectionState) { oldValue, newValue in
            if oldValue == .preparingSupport, newValue == .disconnected {
                beginGOGLogin()
            }
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
        .sheet(isPresented: $showsGOGAuthorizationCode) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Finish GOG sign-in", systemImage: "person.badge.key.fill")
                    .font(.title2.weight(.semibold))
                Text("After GOG signs you in, copy the final page URL or its code value and paste it here. Boreal gives the one-time code directly to heroic-gogdl; your password and browser session remain with GOG.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $gogAuthorizationCode)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("Cancel", role: .cancel) {
                        showsGOGAuthorizationCode = false
                        gogAuthorizationCode = ""
                    }
                    Spacer()
                    Button("Connect", systemImage: "link") {
                        showsGOGAuthorizationCode = false
                        store.connectGOG(authorizationCode: gogAuthorizationCode)
                        gogAuthorizationCode = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gogAuthorizationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(26)
            .frame(width: 540)
        }
    }

    @ViewBuilder private var cloudSaveContent: some View {
        switch store.gogConnectionState {
        case .checking:
            progressView("Checking GOG account…")
        case .supportNotInstalled:
            accountRequiredView(
                title: "GOG support is not ready",
                message: "Prepare GOG support before connecting the account used for Cloud Saves.",
                actionTitle: "Prepare GOG support",
                action: { store.prepareGOGSupport() }
            )
        case .preparingSupport:
            progressView("Preparing GOG support…")
        case .authenticating:
            progressView("Connecting GOG account…")
        case .disconnected:
            accountRequiredView(
                title: "Connect your GOG account",
                message: "Synchronize this game's saves with GOG Cloud between Boreal and your other devices.",
                actionTitle: "Connect GOG account",
                action: { beginGOGLogin() }
            )
        case .failed(let reason):
            accountFailureView(reason: reason)
        case .connected:
            connectedCloudSaveContent
        }
    }

    @ViewBuilder private var connectedCloudSaveContent: some View {
        if let setupMessage {
            setupView(message: setupMessage)
        } else {
            switch status.state {
            case .checking:
                progressView("Checking cloud saves…")
            case .unavailable(let reason):
                unavailableView(reason: reason)
            case .failed(let reason):
                syncFailureView(reason: reason)
            case .needsConfiguration:
                pathConfigurationView
            case .synced, .syncing, .conflict:
                if status.resolvedURL == nil {
                    pathConfigurationView
                } else {
                    readyCloudSaveView
                }
            }
        }
    }

    private var readyCloudSaveView: some View {
        VStack(alignment: .leading, spacing: 18) {
            summarySection
            saveLocationSection

            Toggle("Automatic sync before launch and after exit", isOn: Binding(
                get: { automaticSync },
                set: setAutomaticSync
            ))
            .toggleStyle(.switch)

            if status.state == .conflict {
                conflictView
            } else {
                Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                    store.syncCloudSaves(for: game)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isBusy)
            }

            DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Button("Download from Cloud", systemImage: "arrow.down.circle") {
                            pendingDirection = .useCloud
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                        Button("Upload to Cloud", systemImage: "arrow.up.circle") {
                            pendingDirection = .useLocal
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                    }
                    Button("Open Save Folder", systemImage: "folder") {
                        store.openCloudSaveFolder(for: game)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .font(.callout.weight(.medium))
        }
    }

    private var pathConfigurationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Save location")
                    .font(.headline)
                Text("No save folder was detected. Choose the actual Windows folder used by this game; Boreal will not sync a guessed or empty folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            saveLocationSection
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    summaryMetric("Last synchronization", value: status.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    summaryMetric("Save files", value: "\(status.local.fileCount) local · \(status.cloud.fileCount) cloud")
                    summaryMetric("Cloud usage", value: ByteCountFormatter.string(fromByteCount: status.cloud.totalBytes, countStyle: .file))
                }
                VStack(alignment: .leading, spacing: 10) {
                    summaryMetric("Last synchronization", value: status.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    summaryMetric("Save files", value: "\(status.local.fileCount) local · \(status.cloud.fileCount) cloud")
                    summaryMetric("Cloud usage", value: ByteCountFormatter.string(fromByteCount: status.cloud.totalBytes, countStyle: .file))
                }
            }
            if status.lastUploadedCount > 0 || status.lastDownloadedCount > 0 || status.lastDeletedCount > 0 {
                Text(lastTransferDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryMetric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveLocationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditingPath {
                Text("Windows path")
                    .font(.callout.weight(.medium))
                TextField(#"C:\Users\boreal\Documents\Game\Saves"#, text: $windowsPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                HStack {
                    Button("Cancel") {
                        isEditingPath = false
                    }
                    Spacer()
                    Button("Save") {
                        savePath()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingPath || windowsPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("Restore automatic detection", systemImage: "wand.and.stars") {
                    windowsPath = ""
                    savePath()
                }
                .buttonStyle(.link)
                .disabled(isSavingPath)
            } else if let displayPath = currentWindowsPath {
                HStack(alignment: .top, spacing: 12) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayPath)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            if let actualURL = status.resolvedURL {
                                Text(actualURL.path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                            if let pathSource = status.pathSource {
                                Text(pathSource == .detected ? "Detected automatically" : "Configured manually")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                    }
                    Spacer(minLength: 12)
                    Button("Change") {
                        windowsPath = displayPath
                        isEditingPath = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Label("No save folder detected", systemImage: "folder.badge.questionmark")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Detect again", systemImage: "wand.and.stars") {
                        windowsPath = ""
                        savePath()
                    }
                    .buttonStyle(.bordered)
                    Button("Choose manually") {
                        windowsPath = ""
                        isEditingPath = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var currentWindowsPath: String? {
        if let value = status.windowsPath, !value.isEmpty { return value }
        let configured = windowsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? nil : configured
    }

    private func progressView(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func accountRequiredView(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
            Button(actionTitle, systemImage: "link", action: action)
                .buttonStyle(.borderedProminent)
        }
    }

    private func accountFailureView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("GOG account unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(reason).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Check again", systemImage: "arrow.clockwise") { store.refreshGOGConnection() }
                    .buttonStyle(.bordered)
                Button("Open GOG sign-in", systemImage: "link") { beginGOGLogin() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func setupView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup required", systemImage: "wrench.and.screwdriver")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func unavailableView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cloud Saves unavailable", systemImage: "minus.circle")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(reason).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func syncFailureView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Synchronization failed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(reason).font(.callout).foregroundStyle(.secondary)
            Button("Try again", systemImage: "arrow.clockwise") {
                store.refreshCloudSaveStatus(for: game)
            }
            .buttonStyle(.borderedProminent)
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
        switch store.gogConnectionState {
        case .checking:
            Label("Checking account…", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
        case .supportNotInstalled, .preparingSupport:
            Label("GOG support required", systemImage: "wrench.and.screwdriver")
                .foregroundStyle(.orange)
        case .authenticating:
            Label("Connecting…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.cyan)
        case .disconnected:
            Label("GOG not connected", systemImage: "person.crop.circle.badge.xmark")
                .foregroundStyle(.orange)
        case .failed:
            Label("GOG unavailable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .connected:
            if let setupMessage {
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
                    Label("Sync failed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.orange)
                case .unavailable:
                    Label("Unavailable", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }
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
            Label("Save conflict", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Local and GOG Cloud saves changed since the last synchronization. Choose which copy to use.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
        .padding(14)
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

    private func setAutomaticSync(_ newValue: Bool) {
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

    private func beginGOGLogin() {
        if store.gogConnectionState == .supportNotInstalled {
            store.prepareGOGSupport()
            return
        }
        let value = "https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=client2"
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
        showsGOGAuthorizationCode = true
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
                isEditingPath = false
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
