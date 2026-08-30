import SwiftUI
import Charts

struct DownloadsView: View {
    @Environment(BorealStore.self) private var store
    @AppStorage("developerMode") private var developerMode = false
    @State private var showsRuntimeDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Downloads").font(.largeTitle.bold())
                    Text("Manage game transfers, installations, and the shared components Boreal uses to run them.")
                        .foregroundStyle(.secondary)
                }
                downloadOverview
                gameOperations
                componentsSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await store.refreshRuntimeStatuses() }
    }

    private var downloadOverview: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            DownloadSummaryTile(
                title: "ACTIVE",
                value: "\(activeOperationCount)",
                detail: activeOperationCount == 1 ? "transfer in progress" : "transfers in progress",
                symbol: "arrow.down.circle.fill",
                tint: .cyan
            )
            DownloadSummaryTile(
                title: "PAUSED",
                value: "\(resumableOperationCount)",
                detail: resumableOperationCount == 1 ? "ready to resume" : "ready to resume",
                symbol: "pause.circle.fill",
                tint: .secondary
            )
            DownloadSummaryTile(
                title: "WAITING",
                value: "\(waitingOperationCount)",
                detail: "managed by a provider",
                symbol: "clock.fill",
                tint: .indigo
            )
            DownloadSummaryTile(
                title: "ATTENTION",
                value: "\(failedOperationCount)",
                detail: failedOperationCount == 1 ? "item needs action" : "items need action",
                symbol: "exclamationmark.triangle.fill",
                tint: failedOperationCount > 0 ? .orange : .secondary
            )
        }
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
            if sortedGameOperations.isEmpty {
                ContentUnavailableView {
                    Label("No Game Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Games started from Steam, Epic Games, or GOG will appear here with their current status and controls.")
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.separator.opacity(0.55)) }
            } else {
                ForEach(sortedGameOperations, id: \.game.id) { operation in
                    DownloadOperationCard(
                        game: operation.game,
                        state: operation.state,
                        record: store.storeDownloadRecord(for: operation.game),
                        onPause: { store.cancelStoreGameOperation(operation.game) },
                        onResume: { store.resumeStoreGameOperation(operation.game) },
                        onRemove: { store.clearStoreGameOperation(for: operation.game) }
                    )
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

    private var runtimeList: some View {
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
                }.padding(16)
                if index < store.runtimeStatuses.count - 1 { Divider().padding(.leading, 66) }
            }
        }
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
            if runtime.origin == .localImport { return runtime.isVerified ? "Installed · Validated local snapshot" : "Installed local snapshot" }
            return runtime.isVerified ? "Installed · Verified catalog runtime" : "Installed"
        case .available:
            if let size = runtime.compressedSize, size > 0 { return "\(runtime.engine.displayName) runtime · \(store.formattedBytes(size))" }
            return "\(runtime.engine.displayName) runtime"
        case .preparing: return "Downloading and verifying…"
        case .needsAttention: return "Needs Attention"
        case .loading: return "Checking…"
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
    let game: StoreLibraryGame
    let state: StoreGameOperationState
    let record: StoreDownloadRecord?
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
                phaseStrip(progress.phase)
                progressSection(progress)
                metrics(progress)
                transferChart
                footer(progress)
            } else {
                stateMessage
                footer(nil)
            }
        }
        .padding(20)
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

    private func phaseStrip(_ current: StoreGameOperationPhase) -> some View {
        HStack(spacing: 8) {
            ForEach(StoreGameOperationPhase.allCasesForDisplay, id: \.self) { phase in
                let state = phaseDisplayState(phase, current: current)
                HStack(spacing: 6) {
                    Image(systemName: state.symbol)
                    Text(phase.title)
                        .lineLimit(1)
                }
                .font(.caption.weight(state == .current ? .semibold : .regular))
                .foregroundStyle(state.foregroundStyle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(state == .current ? Color.accentColor.opacity(0.14) : Color.clear, in: Capsule())
            }
        }
        .padding(4)
        .background(.black.opacity(0.12), in: Capsule())
    }

    private func phaseDisplayState(
        _ phase: StoreGameOperationPhase,
        current: StoreGameOperationPhase
    ) -> DownloadPhaseDisplayState {
        let phases = StoreGameOperationPhase.allCasesForDisplay
        guard let phaseIndex = phases.firstIndex(of: phase),
              let currentIndex = phases.firstIndex(of: current) else { return .upcoming }
        if phaseIndex < currentIndex { return .complete }
        if phaseIndex == currentIndex { return .current }
        return .upcoming
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
                Text(progress.estimatedTimeRemaining.map { "About \($0) remaining" } ?? "Time remaining unavailable")
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
        switch (progress.transferred, progress.total) {
        case let (.some(completed), .some(total)): "\(completed) of \(total)"
        case let (.some(completed), nil): completed
        case (nil, .some(let total)): "Total: \(total)"
        case (nil, nil): "Size information unavailable"
        }
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

private struct DownloadSummaryTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(value).font(.title2.bold().monospacedDigit())
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.11)) }
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

private struct TransferChartPoint: Identifiable {
    let timestamp: Date
    let bytesPerSecond: Double
    let kind: String
    var id: String { "\(timestamp.timeIntervalSinceReferenceDate)-\(kind)" }
}

private enum DownloadPhaseDisplayState {
    case complete
    case current
    case upcoming

    var symbol: String {
        switch self {
        case .complete: "checkmark.circle.fill"
        case .current: "circle.inset.filled"
        case .upcoming: "circle"
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .complete: .green
        case .current: .primary
        case .upcoming: .secondary
        }
    }
}

private extension View {
    func downloadStatusBadge() -> some View {
        font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.16), in: Capsule())
    }
}

private extension StoreGameOperationPhase {
    static var allCasesForDisplay: [StoreGameOperationPhase] {
        [.preparing, .downloading, .installing, .verifying]
    }
}
