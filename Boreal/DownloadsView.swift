import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct DownloadsView: View {
    @Environment(BorealStore.self) private var store
    @AppStorage("developerMode") private var developerMode = false
    @State private var showsRuntimeDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                downloadsHeader
                if let operation = focusedOperation {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            downloadWorkspace(operation)
                            downloadInspector(operation)
                                .frame(width: 286)
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            downloadWorkspace(operation)
                            downloadInspector(operation)
                        }
                    }
                } else {
                    gameOperations
                    componentsSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await store.refreshRuntimeStatuses() }
    }

    private var downloadsHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Downloads").font(.largeTitle.bold())
                Text(downloadQueueSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.hasPausableStoreGameOperations {
                Button("Pause All", systemImage: "pause.fill") { store.pauseAllStoreGameOperations() }
                    .buttonStyle(.bordered)
            }
            if store.hasResumableStoreGameOperations {
                Button("Resume All", systemImage: "play.fill") { store.resumeAllStoreGameOperations() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func downloadWorkspace(_ operation: (game: StoreLibraryGame, state: StoreGameOperationState)) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DownloadOperationCard(
                game: operation.game,
                state: operation.state,
                record: store.storeDownloadRecord(for: operation.game),
                presentation: .active,
                onPause: { store.cancelStoreGameOperation(operation.game) },
                onResume: { store.resumeStoreGameOperation(operation.game) },
                onRemove: { store.clearStoreGameOperation(for: operation.game) }
            )
            queuePanel(excluding: operation.game.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func queuePanel(excluding focusedID: UUID) -> some View {
        let remaining = sortedGameOperations.filter { $0.game.id != focusedID }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Download Queue").font(.headline)
                if !remaining.isEmpty {
                    Text("\(remaining.count)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.white.opacity(0.07), in: Capsule())
                }
                Spacer()
            }
            .padding(16)
            if remaining.isEmpty {
                Text("No other games are waiting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 16)
            } else {
                Divider().opacity(0.7)
                ForEach(Array(remaining.enumerated()), id: \.element.game.id) { index, item in
                    DownloadQueueRow(
                        game: item.game,
                        state: item.state,
                        record: store.storeDownloadRecord(for: item.game),
                        onPause: { store.cancelStoreGameOperation(item.game) },
                        onResume: { store.resumeStoreGameOperation(item.game) },
                        onRemove: { store.clearStoreGameOperation(for: item.game) }
                    )
                    if index < remaining.count - 1 { Divider().padding(.leading, 70).opacity(0.7) }
                }
            }
        }
        .downloadPanel()
    }

    private func downloadInspector(_ operation: (game: StoreLibraryGame, state: StoreGameOperationState)) -> some View {
        let record = store.storeDownloadRecord(for: operation.game)
        return VStack(alignment: .leading, spacing: 12) {
            DownloadInspectorCard(title: "Installation Details") {
                InspectorRow(title: "Provider", value: operation.game.provider.rawValue)
                if let platform = record?.platform {
                    InspectorRow(title: "Platform", value: platform == .nativeMacOS ? "Native macOS" : "Windows")
                }
                if let path = record?.destinationRootPath {
                    InspectorRow(title: "Location", value: path)
                    Button("Open Downloads Folder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path, isDirectory: true)])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
                if let progress = operation.state.progress ?? record?.lastProgress {
                    if let total = progress.totalBytes {
                        InspectorRow(title: "Download Size", value: StoreGameOperationProgress.byteCountString(total))
                    }
                    if let remaining = progress.remainingBytes {
                        InspectorRow(title: "Remaining", value: StoreGameOperationProgress.byteCountString(remaining))
                    }
                }
            }

            DownloadInspectorCard(title: "Actions") {
                if operation.state.isCancellable {
                    InspectorAction(title: "Pause Download", symbol: "pause", action: { store.cancelStoreGameOperation(operation.game) })
                }
                if operation.state.isResumable || store.canResumeStoreGameOperation(operation.game) {
                    InspectorAction(title: "Resume Download", symbol: "play", action: { store.resumeStoreGameOperation(operation.game) })
                }
                if !operation.state.isCancellable {
                    InspectorAction(title: "Remove from Queue", symbol: "xmark", role: .destructive, action: { store.clearStoreGameOperation(for: operation.game) })
                }
            }

            componentsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var focusedOperation: (game: StoreLibraryGame, state: StoreGameOperationState)? {
        activeGameOperations.first ?? sortedGameOperations.first
    }

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Components").font(.title3.bold())
                Text("Compatibility runtimes shared by Windows games.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Group {
                if let operation = store.runtimeOperationDetail {
                    VStack(spacing: 13) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        Text("Setting up Boreal").font(.headline)
                        Text(operation).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        ProgressView()
                            .controlSize(.large)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
                    .padding(.top, 42)
                } else if store.runtimeStatuses.contains(where: isInstalledRuntime) {
                    runtimeList
                } else if let runtime = store.runtimeStatuses.first(where: { $0.state == .available }) {
                    prerequisiteView(for: runtime)
                } else {
                    unavailableView
                }
            }
        }
    }

    private func isInstalledRuntime(_ runtime: RuntimeStatus) -> Bool {
        runtime.source == .installed
    }

    private var gameOperations: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Game Downloads").font(.title3.bold())
                    Text(downloadQueueSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.hasPausableStoreGameOperations {
                    Button("Pause All", systemImage: "pause.fill") { store.pauseAllStoreGameOperations() }
                        .buttonStyle(.plain)
                }
                if store.hasResumableStoreGameOperations {
                    Button("Resume All", systemImage: "play.fill") { store.resumeAllStoreGameOperations() }
                        .buttonStyle(.bordered)
                }
            }
            if activeGameOperations.isEmpty && queuedGameOperations.isEmpty {
                ContentUnavailableView {
                    Label("No Game Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Games started from Steam, Epic Games, or GOG will appear here with their current status and controls.")
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.separator.opacity(0.55)) }
            } else {
                ForEach(activeGameOperations, id: \.game.id) { operation in
                    DownloadOperationCard(
                        game: operation.game,
                        state: operation.state,
                        record: store.storeDownloadRecord(for: operation.game),
                        presentation: .active,
                        onPause: { store.cancelStoreGameOperation(operation.game) },
                        onResume: { store.resumeStoreGameOperation(operation.game) },
                        onRemove: { store.clearStoreGameOperation(for: operation.game) }
                    )
                }
                if !queuedGameOperations.isEmpty {
                    HStack {
                        Text("Queue").font(.headline)
                        Text("\(queuedGameOperations.count)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.background.secondary, in: Capsule())
                        Spacer()
                    }
                    .padding(.top, activeGameOperations.isEmpty ? 0 : 6)
                    ForEach(queuedGameOperations, id: \.game.id) { operation in
                        DownloadOperationCard(
                            game: operation.game,
                            state: operation.state,
                            record: store.storeDownloadRecord(for: operation.game),
                            presentation: .queued,
                            onPause: { store.cancelStoreGameOperation(operation.game) },
                            onResume: { store.resumeStoreGameOperation(operation.game) },
                            onRemove: { store.clearStoreGameOperation(for: operation.game) }
                        )
                    }
                }
            }
        }
    }

    private var downloadQueueSummary: String {
        guard !store.activeStoreGameOperations.isEmpty else { return "Your transfer queue is empty" }
        var values: [String] = []
        if activeOperationCount > 0 { values.append("\(activeOperationCount) active") }
        if resumableOperationCount > 0 { values.append("\(resumableOperationCount) paused") }
        if waitingOperationCount > 0 { values.append("\(waitingOperationCount) waiting") }
        if failedOperationCount > 0 { values.append("\(failedOperationCount) needs attention") }
        return values.joined(separator: " · ")
    }

    private var activeOperationCount: Int {
        store.activeStoreGameOperations.filter { $0.state.isCancellable }.count
    }

    private var resumableOperationCount: Int {
        store.activeStoreGameOperations.filter { $0.state.isResumable }.count
    }

    private var waitingOperationCount: Int {
        store.activeStoreGameOperations.filter {
            if case .awaitingProvider = $0.state { return true }
            return false
        }.count
    }

    private var failedOperationCount: Int {
        store.activeStoreGameOperations.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
    }

    private var sortedGameOperations: [(game: StoreLibraryGame, state: StoreGameOperationState)] {
        store.activeStoreGameOperations.sorted { lhs, rhs in
            if lhs.state.isCancellable != rhs.state.isCancellable { return lhs.state.isCancellable }
            return lhs.game.name.localizedStandardCompare(rhs.game.name) == .orderedAscending
        }
    }

    private var activeGameOperations: [(game: StoreLibraryGame, state: StoreGameOperationState)] {
        sortedGameOperations.filter { $0.state.isCancellable }
    }

    private var queuedGameOperations: [(game: StoreLibraryGame, state: StoreGameOperationState)] {
        sortedGameOperations.filter { !$0.state.isCancellable }
    }

    private var runtimeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button("Check Again", systemImage: "arrow.clockwise") {
                    Task { await store.refreshRuntimeStatuses() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
            ForEach(Array(store.runtimeStatuses.enumerated()), id: \.element.id) { index, runtime in
                HStack(spacing: 14) {
                    Image(systemName: runtime.isVerified ? "checkmark.seal.fill" : "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(runtime.isVerified ? Color.green : Color.accentColor)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(runtime.name).font(.headline)
                        Text(runtimeDetail(runtime)).font(.callout).foregroundStyle(.secondary)
                        if developerMode {
                            Text("\(runtime.engine.displayName) \(runtime.wineVersion) · \(runtime.architecture.rawValue) · \(runtime.engine.graphicsName)")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    runtimeAction(runtime)
                    if runtime.source == .installed, runtime.engine == .wine {
                        Menu {
                            Button("Install DXVK") { store.downloadGraphicsComponent(.dxvk, into: runtime.id) }
                            Button("Install DXMT") { store.downloadGraphicsComponent(.dxmt, into: runtime.id) }
                            Divider()
                            Menu("Advanced") {
                                Button("Import DXMT Package…") { selectGraphicsPackage(.dxmt, for: runtime) }
                                Button("Import DXVK Package…") { selectGraphicsPackage(.dxvk, for: runtime) }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Manage graphics translation components")
                    }
                }.padding(16)
                if index < store.runtimeStatuses.count - 1 { Divider().padding(.leading, 66) }
            }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.7), lineWidth: 0.5))

            if !store.runtimeComponentUpdates.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(store.runtimeComponentUpdates.enumerated()), id: \.element.id) { index, update in
                        HStack(spacing: 14) {
                            Image(systemName: update.state == .available ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(update.state == .available ? Color.accentColor : Color.green)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(update.component.displayName).font(.headline)
                                Text(componentUpdateDetail(update)).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if update.state == .available {
                                Button("Update") { store.updateRuntimeComponent(update) }.buttonStyle(.borderedProminent)
                            } else if update.state == .notInstalled {
                                Button("Install") { store.updateRuntimeComponent(update) }.buttonStyle(.bordered)
                            } else {
                                Label("Current", systemImage: "checkmark").foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        if index < store.runtimeComponentUpdates.count - 1 { Divider().padding(.leading, 66) }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.7), lineWidth: 0.5))
            }
            if let error = store.runtimeComponentUpdateError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            ForEach(store.localRuntimeCandidates) { candidate in
                localRuntimeRow(candidate)
            }
        }
    }

    private func selectGraphicsPackage(_ backend: WineGraphicsBackend, for runtime: RuntimeStatus) {
        let panel = NSOpenPanel()
        panel.title = "Choose Extracted \(backend.displayName) Package"
        panel.message = backend == .dxmt
            ? "Choose an extracted folder or ZIP containing the official DXMT 64-bit DLLs."
            : "Choose an extracted folder or ZIP containing a macOS-compatible DXVK package and its DLLs."
        panel.prompt = "Install"
        panel.allowedContentTypes = [.zip]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        store.installGraphicsComponent(backend, from: source, into: runtime.id)
    }

    private func localRuntimeRow(_ candidate: LocalRuntimeCandidate) -> some View {
        HStack(spacing: 14) {
            Image(systemName: candidate.engine == .gamePortingToolkit ? "cpu.fill" : "shippingbox.and.arrow.backward.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName).font(.headline)
                Text("Available to import · \(candidate.engine.graphicsName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Import") { store.importLocalRuntime(id: candidate.id) }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.7), lineWidth: 0.5))
    }

    private func prerequisiteView(for runtime: RuntimeStatus) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "shippingbox")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Boreal Runtime Required").font(.title3).fontWeight(.semibold)
            Text("Components depend on the Boreal Runtime.\nInstall it to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Install Runtime") { store.prepareRuntime(id: runtime.id) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            Button("Check Again") { Task { await store.refreshRuntimeStatuses() } }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
        .padding(.top, 42)
    }

    @ViewBuilder private var unavailableView: some View {
        if let candidate = store.localRuntimeCandidates.first {
            localRuntimeView(candidate)
        } else {
            switch store.runtimeDiscoveryState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Checking for Boreal Runtime…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
        case .loaded, .failed:
            VStack(spacing: 13) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text("Runtime Unavailable").font(.title3).fontWeight(.semibold)
                Text("Boreal couldn't find a compatible runtime.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Check Again", systemImage: "arrow.clockwise") { Task { await store.refreshRuntimeStatuses() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                Button(showsRuntimeDetails ? "Hide Details" : "Show Details") {
                    withAnimation { showsRuntimeDetails.toggle() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                if showsRuntimeDetails {
                    Text(runtimeDetails)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
            .padding(.top, 42)
            }
        }
    }

    private func localRuntimeView(_ candidate: LocalRuntimeCandidate) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(candidate.engine == .gamePortingToolkit ? "Use Game Porting Toolkit" : "Use Installed Wine").font(.title3).fontWeight(.semibold)
            Text("Boreal found \(candidate.displayName) \(candidate.wineVersion). It can copy and validate this \(candidate.engine.displayName) installation as an isolated, read-only runtime snapshot.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 540)
            Button("Import \(candidate.displayName)", systemImage: "square.and.arrow.down") {
                store.importLocalRuntime(id: candidate.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
            Text("The original app stays unchanged. Boreal validates the copy and runs an isolated Windows-environment smoke test before making it available.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
        .padding(.top, 42)
    }

    private var runtimeDetails: String {
        if case .failed(let details) = store.runtimeDiscoveryState { return details }
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif
        return "Runtime catalog\nNo compatible runtime returned.\n\nArchitecture: \(architecture)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nChannel: stable"
    }

    private func runtimeDetail(_ runtime: RuntimeStatus) -> String {
        if let detail = runtime.detail { return detail }
        switch runtime.state {
        case .installed:
            if runtime.origin == .localImport { return runtime.isVerified ? "Installed · Independent validated snapshot" : "Installed independent snapshot" }
            return runtime.isVerified ? "Installed · Verified catalog runtime" : "Installed"
        case .available:
            if let size = runtime.compressedSize, size > 0 { return "\(runtime.engine.displayName) runtime · \(store.formattedBytes(size))" }
            return "\(runtime.engine.displayName) runtime"
        case .preparing: return "Downloading and verifying…"
        case .needsAttention: return "Needs Attention"
        case .loading: return "Checking…"
        }
    }

    private func componentUpdateDetail(_ update: RuntimeComponentUpdate) -> String {
        let target = "for \(update.runtimeName)"
        switch update.state {
        case .notInstalled: return "Available \(update.latestVersion) \(target)"
        case .current: return "\(update.latestVersion) installed \(target)"
        case .available: return "\(update.installedVersion ?? "Installed") → \(update.latestVersion) \(target)"
        }
    }

    @ViewBuilder private func runtimeAction(_ runtime: RuntimeStatus) -> some View {
        switch runtime.state {
        case .installed:
            Label(runtime.origin == .localImport ? "Validated" : "Verified", systemImage: "checkmark").foregroundStyle(.secondary)
        case .available:
            Button("Download") { store.prepareRuntime(id: runtime.id) }.buttonStyle(.bordered)
        case .preparing, .loading:
            ProgressView().controlSize(.small)
        case .needsAttention:
            Label("Needs Attention", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

private struct DownloadOperationCard: View {
    enum Presentation: Equatable {
        case active
        case queued
    }

    let game: StoreLibraryGame
    let state: StoreGameOperationState
    let record: StoreDownloadRecord?
    let presentation: Presentation
    let onPause: () -> Void
    let onResume: () -> Void
    let onRemove: () -> Void

    @State private var showsDetails = false

    private var progress: StoreGameOperationProgress? { state.progress ?? record?.lastProgress }
    private var samples: [StoreDownloadSample] { record?.samples ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let progress {
                progressSection(progress)
                if presentation == .active {
                    metrics(progress)
                    transferChart
                }
                footer(progress)
            } else {
                stateMessage
                footer(nil)
            }
        }
        .padding(presentation == .active ? 20 : 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 15) {
            GameArtworkView(game: game, width: 64, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(game.name)
                    .font(.title3.bold())
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(game.provider.rawValue, systemImage: providerSymbol)
                    if let platform = record?.platform {
                        Label(platform == .nativeMacOS ? "Native macOS" : "Windows", systemImage: platform == .nativeMacOS ? "apple.logo" : "windows")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            statusBadge
            actionButtons
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch state {
        case .installing(let progress), .preparingEnvironment(let progress):
            Label(progress.phase.title, systemImage: progress.phase == .downloading ? "arrow.down.circle.fill" : "gearshape.2.fill")
                .foregroundStyle(.cyan)
                .downloadStatusBadge()
        case .paused:
            Label("Paused", systemImage: "pause.fill")
                .foregroundStyle(.secondary)
                .downloadStatusBadge()
        case .awaitingProvider:
            Label("Waiting", systemImage: "clock.fill")
                .foregroundStyle(.secondary)
                .downloadStatusBadge()
        case .failed:
            Label("Needs Attention", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .downloadStatusBadge()
        }
    }

    @ViewBuilder private var actionButtons: some View {
        if state.isCancellable {
            Button("Pause", systemImage: "pause.fill", action: onPause)
                .buttonStyle(.bordered)
        } else if state.isResumable || record != nil {
            Button("Resume", systemImage: "play.fill", action: onResume)
                .buttonStyle(.borderedProminent)
        }
    }

    private func progressSection(_ progress: StoreGameOperationProgress) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.phase.detail)
                        .font(.headline)
                    Text(progress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let fraction = progress.clampedFraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.title2.bold().monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            if let fraction = progress.clampedFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(BorealDownloadProgressStyle())
                    .scaleEffect(x: 1, y: 1.35, anchor: .center)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            HStack {
                Text(amountSummary(progress))
                Spacer()
                Text(timeRemaining(progress))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func metrics(_ progress: StoreGameOperationProgress) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            DownloadMetric(title: "NETWORK", value: speed(progress.networkBytesPerSecond), symbol: "arrow.down")
            DownloadMetric(title: "DISK USAGE", value: speed(progress.diskBytesPerSecond), symbol: "internaldrive")
            DownloadMetric(title: "PEAK", value: speed(peakSpeed), symbol: "chart.line.uptrend.xyaxis")
            DownloadMetric(title: "ELAPSED", value: elapsed(since: progress.startedAt), symbol: "clock")
        }
    }

    private var transferChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transfer Activity").font(.headline)
                Spacer()
                if !samples.isEmpty {
                    Text("Last \(samples.count) samples")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if chartPoints.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                    Text("Speed history will appear when the transfer starts")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Chart(chartPoints) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Speed", point.bytesPerSecond)
                    )
                    .foregroundStyle(by: .value("Activity", point.kind))
                    .opacity(0.12)
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Speed", point.bytesPerSecond)
                    )
                    .foregroundStyle(by: .value("Activity", point.kind))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
                .chartForegroundStyleScale(["Network": Color.cyan, "Disk": Color.orange])
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel {
                            if let bytes = value.as(Double.self) {
                                Text(shortSpeed(bytes))
                            }
                        }
                    }
                }
                .chartLegend(position: .top, alignment: .trailing, spacing: 14)
                .frame(height: 178)
                .padding(10)
                .background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder private func footer(_ progress: StoreGameOperationProgress?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .paused(_, let reason) = state {
                Label(reason, systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else if case .failed(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            Divider()
            HStack(alignment: .center) {
                DisclosureGroup(isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let path = record?.destinationRootPath {
                            detailRow("Install location", path)
                        }
                        if let updatedAt = record?.updatedAt {
                            detailRow("Last update", updatedAt.formatted(date: .abbreviated, time: .standard))
                        }
                        detailRow("Average network", speed(average(\.networkBytesPerSecond)))
                        detailRow("Average disk", speed(average(\.diskBytesPerSecond)))
                        if let raw = progress?.rawDetail {
                            Text("Latest helper message")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(raw)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Text(showsDetails ? "Hide Details" : "Details")
                        .font(.callout)
                }
                .disclosureGroupStyle(.automatic)
                Spacer()
                if !state.isCancellable {
                    Button("Remove from Queue", role: .destructive, action: onRemove)
                        .buttonStyle(.plain)
                        .font(.callout)
                }
            }
        }
    }

    @ViewBuilder private var stateMessage: some View {
        if case .awaitingProvider(let message) = state {
            Label(message, systemImage: "info.circle")
                .foregroundStyle(.secondary)
        } else if case .failed(let message) = state {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 20)
            Text(value).textSelection(.enabled)
        }
        .font(.caption)
    }

    private var chartPoints: [TransferChartPoint] {
        samples.flatMap { sample in
            var points: [TransferChartPoint] = []
            if let value = sample.networkBytesPerSecond {
                points.append(TransferChartPoint(timestamp: sample.timestamp, bytesPerSecond: value, kind: "Network"))
            }
            if let value = sample.diskBytesPerSecond {
                points.append(TransferChartPoint(timestamp: sample.timestamp, bytesPerSecond: value, kind: "Disk"))
            }
            return points
        }
    }

    private var peakSpeed: Double? {
        chartPoints.map(\.bytesPerSecond).max()
    }

    private func average(_ path: KeyPath<StoreDownloadSample, Double?>) -> Double? {
        let values = samples.compactMap { $0[keyPath: path] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func amountSummary(_ progress: StoreGameOperationProgress) -> String {
        if let transferredBytes = progress.transferredBytes,
           let totalBytes = progress.totalBytes {
            let transferred = StoreGameOperationProgress.byteCountString(transferredBytes)
            let total = StoreGameOperationProgress.byteCountString(totalBytes)
            let remaining = StoreGameOperationProgress.byteCountString(max(0, totalBytes - transferredBytes))
            return "\(transferred) of \(total) · \(remaining) left"
        }
        return switch (progress.transferred, progress.total) {
        case let (.some(completed), .some(total)): "\(completed) of \(total)"
        case let (.some(completed), nil): completed
        case (nil, .some(let total)): "Total: \(total)"
        case (nil, nil): "Size information unavailable"
        }
    }

    private func timeRemaining(_ progress: StoreGameOperationProgress) -> String {
        if let estimated = progress.estimatedTimeRemaining {
            return "About \(estimated) remaining"
        }
        guard progress.phase == .downloading,
              let remaining = progress.remainingBytes,
              remaining > 0,
              let speed = progress.networkBytesPerSecond,
              speed > 0 else {
            return "Time remaining unavailable"
        }
        return "About \(duration(seconds: Double(remaining) / speed)) remaining"
    }

    private func duration(seconds: Double) -> String {
        let wholeSeconds = max(1, Int(seconds.rounded()))
        if wholeSeconds >= 3_600 { return "\(wholeSeconds / 3_600)h \((wholeSeconds % 3_600) / 60)m" }
        if wholeSeconds >= 60 { return "\(wholeSeconds / 60)m \(wholeSeconds % 60)s" }
        return "\(wholeSeconds)s"
    }

    private func speed(_ bytes: Double?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + "/s"
    }

    private func shortSpeed(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + "/s"
    }

    private func elapsed(since start: Date) -> String {
        let seconds = max(0, Int(Date.now.timeIntervalSince(start)))
        if seconds >= 3_600 { return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }

    private var providerSymbol: String {
        switch game.provider {
        case .steam: "s.circle.fill"
        case .epic: "e.circle.fill"
        case .gog: "g.circle.fill"
        }
    }
}

private struct DownloadMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.black.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct DownloadQueueRow: View {
    let game: StoreLibraryGame
    let state: StoreGameOperationState
    let record: StoreDownloadRecord?
    let onPause: () -> Void
    let onResume: () -> Void
    let onRemove: () -> Void

    private var progress: StoreGameOperationProgress? { state.progress ?? record?.lastProgress }

    var body: some View {
        HStack(spacing: 12) {
            GameArtworkView(game: game, width: 42, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            if let fraction = progress?.clampedFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(BorealDownloadProgressStyle())
                    .frame(width: 150)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            } else {
                Text(statusTitle).font(.caption).foregroundStyle(.secondary)
            }
            if state.isCancellable {
                Button("Pause", systemImage: "pause", action: onPause).labelStyle(.iconOnly).buttonStyle(.plain)
            } else if state.isResumable || record != nil {
                Button("Resume", systemImage: "play", action: onResume).labelStyle(.iconOnly).buttonStyle(.plain)
            }
            Button("Remove", systemImage: "xmark", action: onRemove).labelStyle(.iconOnly).buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var subtitle: String {
        if let transferred = progress?.transferredBytes, let total = progress?.totalBytes {
            return "\(StoreGameOperationProgress.byteCountString(transferred)) / \(StoreGameOperationProgress.byteCountString(total))"
        }
        return game.provider.rawValue
    }

    private var statusTitle: String {
        switch state {
        case .installing(let progress), .preparingEnvironment(let progress): progress.phase.title
        case .paused: "Paused"
        case .awaitingProvider: "Queued"
        case .failed: "Needs Attention"
        }
    }
}

private struct DownloadInspectorCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .downloadPanel()
    }
}

private struct InspectorRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

private struct InspectorAction: View {
    let title: String
    let symbol: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .padding(.vertical, 2)
    }
}

private struct TransferChartPoint: Identifiable {
    let timestamp: Date
    let bytesPerSecond: Double
    let kind: String
    var id: String { "\(timestamp.timeIntervalSinceReferenceDate)-\(kind)" }
}

private extension View {
    func downloadPanel() -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            }
    }

    func downloadStatusBadge() -> some View {
        font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.16), in: Capsule())
    }
}
