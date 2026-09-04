import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct StoreGameDetailView: View {
    private enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case compatibility = "Compatibility"
        case activity = "Activity"
        case files = "Files"
    }

    @Environment(BorealStore.self) private var store
    let game: StoreLibraryGame
    var onSelectProducer: (String) -> Void = { _ in }
    @State private var showsInstallationOptions = false
    @State private var showsProgressDetails = false
    @State private var selectedScreenshot: StoreScreenshotSelection?
    @State private var selectedVideo: StoreVideo?
    @State private var showsUninstallConfirmation = false
    @State private var selectedTab: DetailTab = .overview
    @State private var compatibilityApplication: WindowsApplication?

    private var currentGame: StoreLibraryGame { store.storeGame(id: game.id) ?? game }

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        detailTabBar
                        tabContent
                            .padding(20)
                    }
                    .frame(minWidth: 760, maxWidth: .infinity, alignment: .leading)

                    detailRail
                        .frame(width: 286)
                }
                .frame(minWidth: 1046, maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    hero
                    detailTabBar
                    tabContent
                        .padding(20)
                    detailsSidebar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showsInstallationOptions) {
            StoreGameInstallationSheet(
                game: currentGame,
                defaultDestination: store.defaultGameInstallationRoot(for: game.provider)
            ) { destination in
                if game.provider == .steam { store.installSteamWindowsGame(currentGame) }
                else { store.installStoreGame(currentGame, destinationRoot: destination) }
            }
        }
        .task(id: game.id) {
            await store.loadCommunityCompatibility(for: game.id)
        }
        .task(id: game.id) {
            await store.loadStoreGameSizeIfNeeded(for: game.id)
        }
        .sheet(item: $selectedVideo) { video in
            StoreVideoPlayerView(video: video)
        }
        .sheet(item: $selectedScreenshot) { screenshot in
            StoreScreenshotViewer(screenshot: screenshot, gameName: game.name)
        }
        .sheet(item: $compatibilityApplication) { application in
            WineCompatibilityConfigurator(application: store.application(id: application.id) ?? application)
        }
        .task(id: game.id) {
            store.refreshSteamMetadataIfNeeded(for: game)
        }
        .task(id: game.id) {
            await store.loadSteamCurrentPlayerCountIfNeeded(for: game.id)
        }
        .confirmationDialog("Uninstall \(currentGame.name)?", isPresented: $showsUninstallConfirmation) {
            Button("Uninstall Game", role: .destructive) { uninstallGame() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(uninstallConfirmationMessage)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground
            LinearGradient(
                colors: [.black.opacity(0.04), .black.opacity(0.38), .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            ViewThatFits(in: .horizontal) {
                heroWideContent
                heroCompactContent
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 272, maxHeight: 300, alignment: .bottomLeading)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private var heroWideContent: some View {
        HStack(alignment: .bottom, spacing: 24) {
            heroArtwork
            heroIdentity
            Spacer(minLength: 20)
        }
    }

    private var heroCompactContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 18) {
                GameArtworkView(game: currentGame, width: 112, height: 158)
                heroIdentity
            }
        }
    }

    private var heroArtwork: some View {
        GameArtworkView(game: currentGame, width: 156, height: 218)
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private var heroIdentity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(currentGame.provider.rawValue, systemImage: currentGame.provider.symbol)
                Text("IN YOUR LIBRARY")
            }
            .font(.caption.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(.white.opacity(0.72))
            Text(currentGame.name)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            if let developer = currentGame.developer {
                Button {
                    onSelectProducer(developer)
                } label: {
                    Text(developer)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.76))
                }
                .buttonStyle(.plain)
                .help("Show all games by \(developer)")
            }
            HStack(spacing: 8) {
                StorePlatformBadge(game: currentGame)
                StoreRatingBadge(rating: currentGame.storeRating)
                if currentGame.supportsNativeMacOS != true,
                   let compatibility = currentGame.compatibility {
                    MacCompatibilityBadge(rating: compatibility.tier.rating)
                }
            }
            primaryActions
                .padding(.top, 4)
        }
    }

    private var visibleTabs: [DetailTab] {
        DetailTab.allCases.filter { tab in
            switch tab {
            case .overview, .activity: true
            case .compatibility: currentGame.supportsNativeMacOS != true && currentGame.compatibility != nil
            case .files: currentGame.installPath != nil || linkedApplication != nil
            }
        }
    }

    private var detailTabBar: some View {
        HStack(spacing: 28) {
            ForEach(visibleTabs, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Capsule().fill(Color.accentColor).frame(height: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .background(.black.opacity(0.10))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewMainColumn
        case .compatibility:
            compatibilitySection
        case .activity:
            libraryOverview
        case .files:
            installationFilesSection
        }
    }

    private var detailRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if storeOperation != nil {
                operationStatus
            }
            detailsSidebar
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 760, alignment: .topLeading)
        .background(.black.opacity(0.12))
        .overlay(alignment: .leading) { Divider() }
    }

    private var overviewMainColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            operationAndLibraryOverview
            mediaSection
            overviewEditorialGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var operationAndLibraryOverview: some View {
        if storeOperation != nil {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    operationStatus
                        .frame(maxWidth: .infinity, alignment: .leading)
                    libraryOverview
                        .frame(width: 430)
                }
                VStack(alignment: .leading, spacing: 12) {
                    operationStatus
                    libraryOverview
                }
            }
        } else {
            libraryOverview
        }
    }

    private var overviewEditorialGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                aboutGameSection
                if currentGame.supportsNativeMacOS != true,
                   currentGame.compatibility != nil {
                    compatibilitySection
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                aboutGameSection
                if currentGame.supportsNativeMacOS != true,
                   currentGame.compatibility != nil {
                    compatibilitySection
                }
            }
        }
    }

    @ViewBuilder private var aboutGameSection: some View {
        if let summary = currentGame.summary, !summary.isEmpty {
            detailCard("About this game", symbol: "text.alignleft") {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var heroBackground: some View {
        if let value = currentGame.backgroundImageURL ?? currentGame.headerImageURL, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: storeImageFailurePlaceholder
                case .empty: Color.accentColor.opacity(0.12).overlay { ProgressView().tint(.white) }
                @unknown default: Color.accentColor.opacity(0.12)
                }
            }
        } else {
            LinearGradient(colors: [.indigo.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder private var primaryActions: some View {
        HStack(spacing: 10) {
            if game.provider == .steam {
                if currentGame.isInstalled, currentGame.installedPlatform == .nativeMacOS, currentGame.installPath != nil {
                    Button("Play", systemImage: "play.fill") { openNativeInstallation() }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                } else if let app = linkedApplication {
                    runtimeLaunchControl(for: app, playTitle: "Play")
                } else if currentGame.supportsNativeMacOS == true {
                    Button(currentGame.isInstalled ? "Play" : "Install", systemImage: currentGame.isInstalled ? "play.fill" : "arrow.down.circle.fill") { openSteam() }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                } else if currentGame.supportsWindows == true, storeOperation == nil {
                    Button("Install Windows Version", systemImage: "arrow.down.circle.fill") { showsInstallationOptions = true }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                } else {
                    Button("Open in Steam", systemImage: "arrow.up.right.square") { openSteam() }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                }
            } else if currentGame.isInstalled {
                if currentGame.installedPlatform == .nativeMacOS {
                    Button("Play", systemImage: "play.fill") { openNativeInstallation() }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                } else if let app = linkedApplication {
                    runtimeLaunchControl(for: app, playTitle: "Play")
                } else if storeOperation == nil {
                    runtimePreparationMenu
                }
            } else if storeOperation == nil {
                Button(installButtonTitle, systemImage: "arrow.down.circle.fill") { showsInstallationOptions = true }
                    .buttonStyle(BorealPrimaryActionButtonStyle())
            }
            if linkedApplication != nil || currentGame.isInstalled {
                gameSettingsMenu
            }
            moreActionsMenu
        }
        .tint(.cyan)
    }

    private var gameSettingsMenu: some View {
        Menu {
            if let app = linkedApplication {
                Button("Compatibility Settings…", systemImage: "slider.horizontal.3") {
                    compatibilityApplication = app
                }
                let gameActions = store.auxiliaryExecutables(for: app)
                if !gameActions.isEmpty {
                    Section("Game Actions") {
                        ForEach(gameActions) { action in
                            Button(action.displayName, systemImage: action.role.symbol) {
                                store.runAuxiliaryExecutable(action, for: app.id)
                            }
                            .disabled(app.status == .running || app.status.isBusy || storeOperation != nil)
                        }
                    }
                }
                Divider()
            }
            if let app = linkedApplication, canChooseRuntime(for: app) {
                Section("Runtime") {
                    runtimeSettingsButton(.gamePortingToolkit, for: app)
                    runtimeSettingsButton(.wine, for: app)
                }
                Divider()
            }
            if currentGame.installPath != nil {
                Button("Show Game Files", systemImage: "folder") { showGameFiles() }
            }
            if !currentGame.isInstalled && linkedApplication == nil {
                Button("Locate Installed Game…", systemImage: "folder.badge.plus") { locateInstalledGame() }
            }
        } label: {
            squareMenuLabel(symbol: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Game settings")
        .accessibilityLabel("Game settings")
    }

    private var moreActionsMenu: some View {
        Menu {
            if currentGame.provider == .steam {
                Button("View Steam Store Page", systemImage: "arrow.up.right.square") { openStorePage() }
            }
            if currentGame.isInstalled, store.supportsStoreGameUpdate(currentGame) {
                Button("Check for Updates", systemImage: "arrow.triangle.2.circlepath") {
                    store.updateStoreGame(currentGame)
                }
                .disabled(storeOperation != nil)
            }
            if currentGame.isInstalled, store.supportsStoreGameVerification(currentGame) {
                Button("Verify Game Files", systemImage: "checkmark.shield") {
                    store.verifyStoreGame(currentGame)
                }
                .disabled(storeOperation != nil)
            }
            if currentGame.isInstalled || linkedApplication != nil {
                Divider()
                Button("Uninstall…", systemImage: "trash", role: .destructive) { showsUninstallConfirmation = true }
            }
        } label: {
            squareMenuLabel(symbol: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    @ViewBuilder private func runtimeLaunchControl(for app: WindowsApplication, playTitle: String) -> some View {
        if app.status == .running {
            Button("Stop", systemImage: "stop.fill") { store.toggleRunning(app.id) }
                .buttonStyle(BorealPrimaryActionButtonStyle())
        } else {
            Button(playTitle, systemImage: "play.fill") { store.toggleRunning(app.id) }
                .buttonStyle(BorealPrimaryActionButtonStyle())
                .disabled(app.status.isBusy || app.status == .unavailable || storeOperation != nil)
        }
    }

    private func runtimeSettingsButton(_ engine: RuntimeEngine, for app: WindowsApplication) -> some View {
        let isCurrent = currentRuntimeEngine(for: app) == engine
        return Button {
            if !isCurrent {
                store.recreateEnvironment(app.id, with: engine)
            }
        } label: {
            Label(
                engine.displayName + " (" + engine.graphicsName + ")" + (isCurrent ? " · Current" : ""),
                systemImage: engine == .gamePortingToolkit ? "cpu" : "shippingbox"
            )
        }
        .disabled(
            isCurrent
                || (engine == .gamePortingToolkit && store.runtimeCompatibilityIssue(for: app, engine: engine) != nil)
        )
    }

    private func squareMenuLabel(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 40, height: 40)
            .background(.black.opacity(0.34))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.14))
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func canChooseRuntime(for app: WindowsApplication) -> Bool {
        guard let provider = app.storeProvider else { return false }
        return [.epic, .gog].contains(provider)
    }

    private func currentRuntimeEngine(for app: WindowsApplication) -> RuntimeEngine? {
        guard let graphics = store.environment(id: app.environmentID)?.graphics else { return nil }
        return graphics == RuntimeEngine.gamePortingToolkit.graphicsName ? .gamePortingToolkit : .wine
    }

    private var runtimePreparationMenu: some View {
        Menu {
            let recommended = store.recommendedRuntimeEngine(for: currentGame)
            Button("Recommended: \(recommended.displayName)", systemImage: recommended == .gamePortingToolkit ? "cpu.fill" : "shippingbox.fill") {
                store.prepareStoreGame(currentGame, runtimeEngine: recommended)
            }
            Divider()
            Button("Game Porting Toolkit (D3DMetal)", systemImage: "cpu") {
                store.prepareStoreGame(currentGame, runtimeEngine: .gamePortingToolkit)
            }
            Button("Wine (WineD3D)", systemImage: "shippingbox") {
                store.prepareStoreGame(currentGame, runtimeEngine: .wine)
            }
        } label: {
            Label("Prepare to Play", systemImage: "wand.and.stars")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(BorealPrimaryActionButtonStyle())
        .fixedSize()
    }

    @ViewBuilder private var operationStatus: some View {
        if let progress = storeOperation?.progress {
            operationProgress(progress)
        } else if case .awaitingProvider(let message) = storeOperation {
            statusCard(symbol: "info.circle.fill", tint: .secondary) {
                Text(message)
                if game.provider == .steam {
                    Button("Refresh Windows Steam Status", systemImage: "arrow.clockwise") {
                        store.refreshSteamWindowsGame(currentGame)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Dismiss Status") { store.clearStoreGameOperation(for: game) }.buttonStyle(.plain)
            }
        } else if case .failed(let message) = storeOperation {
            statusCard(symbol: "exclamationmark.triangle.fill", tint: .orange) {
                Text(message)
                retryAction
            }
        }
    }

    private func statusCard<Content: View>(symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) { content() }
            Spacer()
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var retryAction: some View {
        if store.canResumeStoreGameOperation(game) {
            Button("Resume Download", systemImage: "arrow.clockwise") { store.resumeStoreGameOperation(game) }
                .buttonStyle(.borderedProminent)
        } else if game.provider == .steam {
            Button("Try Windows Installation Again", systemImage: "arrow.clockwise") {
                store.clearStoreGameOperation(for: game); showsInstallationOptions = true
            }
        } else if currentGame.isInstalled {
            Button("Try Preparation Again", systemImage: "arrow.clockwise") {
                store.clearStoreGameOperation(for: game); store.prepareStoreGame(game)
            }
        } else {
            Button("Try \(preferredPlatformName) Installation Again", systemImage: "arrow.clockwise") {
                store.clearStoreGameOperation(for: game); showsInstallationOptions = true
            }
        }
    }

    private var playtime: String {
        guard game.playtimeMinutes > 0 else { return "Not played" }
        if game.playtimeMinutes < 60 { return "\(game.playtimeMinutes) min" }
        return String(format: "%.1f hours", Double(game.playtimeMinutes) / 60)
    }

    private var libraryOverview: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                overviewMetric("Library status", value: libraryStatus, symbol: libraryStatusSymbol)
                overviewDivider
                overviewMetric("Playtime", value: playtime, symbol: "clock.fill")
                overviewDivider
                overviewMetric(
                    "Last played",
                    value: currentGame.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "Never",
                    symbol: "calendar"
                )
                overviewDivider
                overviewMetric(requiredStorageTitle, value: formattedRequiredStorage, symbol: "internaldrive.fill")
            }
            VStack(alignment: .leading, spacing: 0) {
                overviewMetric("Library status", value: libraryStatus, symbol: libraryStatusSymbol)
                Divider()
                overviewMetric("Playtime", value: playtime, symbol: "clock.fill")
                Divider()
                overviewMetric(
                    "Last played",
                    value: currentGame.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "Never",
                    symbol: "calendar"
                )
                Divider()
                overviewMetric(requiredStorageTitle, value: formattedRequiredStorage, symbol: "internaldrive.fill")
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12)) }
    }

    private func overviewMetric(_ title: String, value: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(height: 28)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .center)
        .padding(.horizontal, 12)
    }

    private var overviewDivider: some View {
        Divider().frame(height: 124)
    }

    private var detailContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                editorialContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                detailsSidebar
                    .frame(width: 310)
            }
            VStack(alignment: .leading, spacing: 26) {
                editorialContent
                detailsSidebar
            }
        }
    }

    private var editorialContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let summary = currentGame.summary, !summary.isEmpty {
                section("About this game") {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
            if currentGame.supportsNativeMacOS != true { compatibilitySection }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formattedDownloadSize: String {
        guard let bytes = currentGame.sizeEstimate?.downloadBytes, bytes > 0 else { return "Not provided" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var requiredStorageTitle: String {
        currentGame.storageBytes.map { $0 > 0 } == true ? "On disk" : "Required space"
    }

    private var formattedRequiredStorage: String {
        if let bytes = currentGame.storageBytes, bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        guard let estimate = currentGame.sizeEstimate,
              let bytes = estimate.installedBytes, bytes > 0 else { return "Checking availability…" }
        let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return estimate.source.isExactManifest ? formatted : "≈ \(formatted)"
    }

    private var sizeSource: String {
        if currentGame.storageBytes.map({ $0 > 0 }) == true { return "Installed files" }
        switch currentGame.sizeEstimate?.source {
        case .gogManifest: return "GOG manifest"
        case .epicManifest: return "Epic manifest"
        case .steamStoreRequirement: return "Steam store requirement"
        case nil: return "Unavailable"
        }
    }

    private var installationLocation: String {
        guard let path = currentGame.installPath else { return "Not installed" }
        return URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    }

    private var storeOperation: StoreGameOperationState? {
        store.storeGameOperation(for: game)
    }

    private func operationProgress(_ progress: StoreGameOperationProgress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(progress.phase.title) \(game.name)")
                        .font(.headline)
                        .lineLimit(1)
                    Text(progress.phase.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let fraction = progress.clampedFraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.title3.bold().monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            if let fraction = progress.clampedFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(BorealDownloadProgressStyle())
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.cyan)
            }

            if !progressSummary(progress).isEmpty {
                Text(progressSummary(progress))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if case .paused(_, let reason) = storeOperation {
                Label(reason, systemImage: "pause.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if progress.rawDetail != nil || storeOperation?.isCancellable == true || storeOperation?.isResumable == true {
                HStack(alignment: .firstTextBaseline) {
                    if let rawDetail = progress.rawDetail {
                        DisclosureGroup("Details", isExpanded: $showsProgressDetails) {
                            Text(rawDetail)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 7)
                        }
                        .font(.callout)
                    }
                    Spacer()
                    if storeOperation?.isCancellable == true {
                        Button("Pause") {
                            store.cancelStoreGameOperation(game)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Pause and keep downloaded files")
                    } else if storeOperation?.isResumable == true {
                        Button("Remove from Queue", role: .destructive) {
                            store.clearStoreGameOperation(for: game)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        Button("Resume") {
                            store.resumeStoreGameOperation(game)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(18)
        .frame(minHeight: 124, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.14)) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(progress.phase.title) \(game.name), \(progress.phase.detail)")
    }

    private func progressSummary(_ progress: StoreGameOperationProgress) -> String {
        var values: [String] = []
        if let transferredBytes = progress.transferredBytes,
           let totalBytes = progress.totalBytes {
            values.append("\(StoreGameOperationProgress.byteCountString(transferredBytes)) of \(StoreGameOperationProgress.byteCountString(totalBytes))")
            values.append("\(StoreGameOperationProgress.byteCountString(max(0, totalBytes - transferredBytes))) left")
        } else if let transferred = progress.transferred, let total = progress.total {
            values.append("\(transferred) of \(total)")
        } else if let total = progress.total {
            values.append("Total: \(total)")
        }
        if let rate = progress.transferRate { values.append(rate) }
        if let remaining = progress.estimatedTimeRemaining {
            values.append("About \(remaining) remaining")
        } else if let remainingBytes = progress.remainingBytes,
                  remainingBytes > 0,
                  let speed = progress.networkBytesPerSecond,
                  speed > 0 {
            let seconds = max(1, Int((Double(remainingBytes) / speed).rounded()))
            let eta = seconds >= 3_600
                ? "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
                : seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
            values.append("About \(eta) remaining")
        }
        return values.joined(separator: "  •  ")
    }

    @ViewBuilder private var mediaSection: some View {
        let screenshots = currentGame.screenshotURLs ?? []
        let videos = currentGame.videos ?? []
        if !screenshots.isEmpty || !videos.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Media").font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(Array(screenshots.enumerated()), id: \.offset) { index, value in
                            if let url = URL(string: value) {
                                Button {
                                    let galleryURLs = screenshots.compactMap(URL.init(string:))
                                    selectedScreenshot = StoreScreenshotSelection(
                                        urls: galleryURLs,
                                        initialIndex: galleryURLs.firstIndex(of: url) ?? index
                                    )
                                } label: {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image): image.resizable().scaledToFill()
                                        case .failure: storeImageFailurePlaceholder
                                        case .empty: Rectangle().fill(.background.secondary).overlay { ProgressView() }
                                        @unknown default: Rectangle().fill(.background.secondary)
                                        }
                                    }
                                    .frame(width: 205, height: 118)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .padding(9)
                                            .background(.ultraThinMaterial, in: Circle())
                                            .padding(9)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("Open screenshot")
                            }
                        }
                        ForEach(videos) { video in
                            Button { selectedVideo = video } label: {
                                ZStack {
                                    if let thumbnail = video.thumbnailURL, let url = URL(string: thumbnail) {
                                        AsyncImage(url: url) { phase in
                                            if let image = phase.image { image.resizable().scaledToFill() }
                                            else { Rectangle().fill(.background.secondary) }
                                        }
                                    }
                                    Color.black.opacity(0.25)
                                    Image(systemName: "play.circle.fill").font(.system(size: 46)).foregroundStyle(.white)
                                }
                                .frame(width: 205, height: 118)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(video.name)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var storeImageFailurePlaceholder: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var detailsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let environment = linkedEnvironment {
                detailCard("Environment", symbol: "flask.fill") {
                    metric("Environment", value: environment.name, symbol: "shippingbox")
                    metric("Runtime", value: environment.runtime, symbol: "gearshape.2")
                    metric("Graphics", value: environment.graphics, symbol: "display")
                    metric("Windows version", value: environment.windowsVersion, symbol: "window.ceiling")
                    metric("Architecture", value: environment.architecture, symbol: "cpu")
                }
            }
            if currentGame.installPath != nil || currentGame.storageBytes != nil || currentGame.sizeEstimate != nil {
                detailCard("Installation", symbol: "folder.fill") {
                    if currentGame.installPath != nil {
                        metric("Location", value: installationLocation, symbol: "folder")
                    }
                    metric(requiredStorageTitle, value: formattedRequiredStorage, symbol: "internaldrive")
                    if currentGame.sizeEstimate?.downloadBytes != nil {
                        metric("Download", value: formattedDownloadSize, symbol: "arrow.down.circle")
                    }
                    if currentGame.installPath != nil {
                        Button("Open installation folder", systemImage: "folder") { showGameFiles() }
                            .buttonStyle(BorealSecondaryActionButtonStyle())
                    }
                }
            }
            detailCard("Actions", symbol: "ellipsis") {
                if currentGame.installPath != nil {
                    Button("Open game folder", systemImage: "folder") { showGameFiles() }
                        .buttonStyle(BorealRailActionButtonStyle())
                }
                if !currentGame.isInstalled && linkedApplication == nil {
                    Button("Locate installed game…", systemImage: "folder.badge.plus") { locateInstalledGame() }
                        .buttonStyle(BorealRailActionButtonStyle())
                }
                if currentGame.provider == .steam {
                    Button("View Steam store page", systemImage: "arrow.up.right.square") { openStorePage() }
                        .buttonStyle(BorealRailActionButtonStyle())
                }
                if currentGame.isInstalled, store.supportsStoreGameUpdate(currentGame) {
                    Button("Check for updates", systemImage: "arrow.triangle.2.circlepath") {
                        store.updateStoreGame(currentGame)
                    }
                    .buttonStyle(BorealRailActionButtonStyle())
                    .disabled(storeOperation != nil)
                }
                if currentGame.isInstalled, store.supportsStoreGameVerification(currentGame) {
                    Button("Verify game files", systemImage: "checkmark.shield") {
                        store.verifyStoreGame(currentGame)
                    }
                    .buttonStyle(BorealRailActionButtonStyle())
                    .disabled(storeOperation != nil)
                }
                if currentGame.isInstalled || linkedApplication != nil {
                    Divider()
                    Button("Uninstall…", systemImage: "trash", role: .destructive) {
                        showsUninstallConfirmation = true
                    }
                    .buttonStyle(BorealRailActionButtonStyle())
                }
            }
        }
    }

    private var installationFilesSection: some View {
        detailCard("Installation", symbol: "folder.fill") {
            if let path = currentGame.installPath {
                metric("Location", value: path, symbol: "folder")
                Button("Open installation folder", systemImage: "folder") { showGameFiles() }
                    .buttonStyle(BorealSecondaryActionButtonStyle())
            }
            if let application = linkedApplication {
                metric("Executable", value: URL(fileURLWithPath: application.executablePath).lastPathComponent, symbol: "doc")
            }
        }
    }

    private var libraryStatus: String {
        if linkedApplication != nil { return "Managed by Boreal" }
        if currentGame.isInstalled { return "Installed" }
        return "In your library"
    }

    private var libraryStatusSymbol: String {
        if linkedApplication?.status == .running { return "play.circle.fill" }
        if linkedApplication != nil { return "checkmark.seal.fill" }
        if currentGame.isInstalled { return "checkmark.circle.fill" }
        return "books.vertical.fill"
    }

    private var actionContext: String {
        if linkedApplication?.status == .running { return "The game is running now." }
        if storeOperation != nil { return "An installation task is currently in progress." }
        if linkedApplication != nil { return "Ready to launch with its configured Boreal runtime." }
        if currentGame.isInstalled { return "Installed locally and ready to open." }
        return "Owned on \(currentGame.provider.rawValue). Install it when you are ready to play."
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailCard<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12)) }
    }

    private var linkedApplication: WindowsApplication? { store.linkedApplication(for: game) }

    private var linkedEnvironment: WindowsEnvironment? {
        guard let application = linkedApplication else { return nil }
        return store.environment(id: application.environmentID)
    }

    private var preferredPlatformName: String {
        currentGame.supportsNativeMacOS == true ? "macOS" : "Windows"
    }

    private var installButtonTitle: String {
        currentGame.supportsNativeMacOS == true ? "Install Native macOS Version" : "Install Windows Version"
    }

    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Mac Compatibility", systemImage: "checkmark.shield.fill")
                .font(.headline)
            if let profile = currentGame.compatibility {
                HStack(alignment: .top, spacing: 18) {
                    MacCompatibilityBadge(rating: profile.tier.rating)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Wine compatibility")
                            .fontWeight(.medium)
                        Text(compatibilitySummary(profile))
                            .font(.callout).foregroundStyle(.secondary)
                        Text("This compatibility estimate is not a guarantee for Boreal's Wine configuration.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No compatibility reports",
                    systemImage: "questionmark.circle",
                    description: Text("Boreal did not find an unambiguous macOS/Wine compatibility result for this title.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.14)) }
    }

    private func compatibilitySummary(_ profile: CommunityCompatibility) -> String {
        var parts = [profile.tier.title]
        if let score = profile.score { parts.append("\(Int(score))/5 stars") }
        if profile.reportCount > 0 { parts.append("\(profile.reportCount.formatted()) reports") }
        if let confidence = profile.confidence, profile.score == nil {
            parts.append("\(confidence.capitalized) confidence")
        }
        if let trending = profile.trendingTier, trending != profile.tier { parts.append("Trending: \(trending.title)") }
        if let date = profile.sourceUpdatedAt, profile.score != nil {
            parts.append("Updated \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showGameFiles() {
        guard let installPath = currentGame.installPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installPath)])
    }

    private func openSteam() {
        let action = currentGame.isInstalled ? "rungameid" : (currentGame.supportsNativeMacOS == true ? "install" : "store")
        if action == "rungameid", currentGame.installedPlatform == .nativeMacOS, let path = currentGame.installPath {
            GameOverlayController.shared.expectNativeGame(
                name: currentGame.name,
                installationURL: URL(fileURLWithPath: path, isDirectory: true)
            )
        }
        if let url = URL(string: "steam://\(action)/\(game.externalID)") { NSWorkspace.shared.open(url) }
    }

    private func openNativeInstallation() {
        guard let path = currentGame.installPath else { return }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let candidate as URL in enumerator {
                if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                    GameOverlayController.shared.expectNativeGame(name: currentGame.name, installationURL: candidate)
                    NSWorkspace.shared.open(candidate)
                    return
                }
            }
        }
        NSWorkspace.shared.open(root)
    }

    private func locateInstalledGame() {
        let panel = NSOpenPanel()
        panel.title = "Locate \(game.name)"
        panel.message = currentGame.supportsNativeMacOS == true
            ? "Choose the installed macOS .app or the main Windows .exe file."
            : "Choose the installed game’s main Windows .exe file."
        panel.prompt = "Add to Boreal"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types = [UTType(filenameExtension: "exe") ?? .data]
        if currentGame.supportsNativeMacOS == true { types.append(.applicationBundle) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.registerExistingGame(game, at: url)
    }

    private func openStorePage() {
        if let url = URL(string: "https://store.steampowered.com/app/\(game.externalID)") { NSWorkspace.shared.open(url) }
    }

    private var uninstallConfirmationMessage: String {
        if game.provider == .steam {
            return "Steam will manage removal of the game. Boreal will open Steam’s uninstall screen."
        }
        if linkedApplication != nil {
            return game.provider == .gog
                ? "This removes the installed game and its Boreal Windows environment. The game files are moved to the Trash."
                : "This removes the installed game and its Boreal Windows environment. Legendary also clears its installation record."
        }
        return game.provider == .gog
            ? "The installed game will be moved to the Trash. Your GOG library ownership is not affected."
            : "Legendary will remove the installed game. Your Epic Games library ownership is not affected."
    }

    private func uninstallGame() {
        if let application = linkedApplication, application.usesStoreMetadataOnly {
            store.removeApplication(application.id)
        } else if game.provider == .steam {
            if let url = URL(string: "steam://uninstall/\(game.externalID)") { NSWorkspace.shared.open(url) }
        } else {
            store.uninstallStoreGame(currentGame)
        }
    }

}

private struct BorealSecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.10 : 0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.14))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct BorealPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 132, minHeight: 40)
            .padding(.horizontal, 4)
            .background(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [Color.indigo.opacity(0.85), Color.blue.opacity(0.85)]
                        : [Color.indigo, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .blue.opacity(0.22), radius: 8, y: 3)
    }
}

private struct BorealSquareActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 40, height: 40)
            .background(.black.opacity(configuration.isPressed ? 0.50 : 0.34))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.14))
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct BorealRailActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct BorealDownloadProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * fraction))
                    .shadow(color: .cyan.opacity(0.35), radius: 6)
            }
        }
        .frame(height: 12)
        .animation(.smooth(duration: 0.25), value: configuration.fractionCompleted)
    }
}

private struct StoreGameInstallationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let game: StoreLibraryGame
    let completion: (URL?) -> Void
    @State private var destination: URL

    init(game: StoreLibraryGame, defaultDestination: URL, completion: @escaping (URL?) -> Void) {
        self.game = game
        self.completion = completion
        _destination = State(initialValue: defaultDestination)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                GameArtworkView(game: game, width: 68, height: 96)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Install \(game.name)").font(.title2.bold())
                    Text(game.provider.rawValue).foregroundStyle(.secondary)
                }
            }

            if game.supportsNativeMacOS == true {
                Label("Native macOS version", systemImage: "apple.logo")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Boreal will download the native Mac release. The Windows/Wine version is used only when a native release is unavailable.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if game.provider == .steam {
                Label("Steam for Windows manages this installation", systemImage: "gamecontroller.fill")
                    .font(.headline)
                Text("Boreal will install Valve’s Windows Steam client in its own Wine prefix. Sign in and choose the game’s library in Steam; Boreal will launch the game through that client.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Installation location").font(.headline)
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill").foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.lastPathComponent).fontWeight(.medium).lineLimit(1)
                            Text(destination.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button("Choose…") { chooseDestination() }
                    }
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Boreal will create a dedicated game folder inside this location.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                storageSummary(title: "Download", value: formattedDownloadSize, symbol: "arrow.down.circle")
                storageSummary(title: "Required", value: formattedRequiredSize, symbol: "internaldrive")
                storageSummary(title: "Space available", value: formattedCapacity, symbol: "externaldrive")
            }

            architectureSummary

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(game.supportsNativeMacOS == true ? "Download Native Version" : (game.provider == .steam ? "Open Windows Steam Installer" : "Download and Install")) {
                    completion(game.provider == .steam ? nil : destination)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(game.provider != .steam && !destinationIsUsable)
            }
        }
        .padding(28)
        .frame(width: 680)
    }

    private var destinationIsUsable: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory)
        if exists { return isDirectory.boolValue && FileManager.default.isWritableFile(atPath: destination.path) }
        return FileManager.default.isWritableFile(atPath: capacityProbeURL.path)
    }

    private var formattedDownloadSize: String {
        guard let bytes = game.sizeEstimate?.downloadBytes, bytes > 0 else { return "Not provided" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var formattedRequiredSize: String {
        if let bytes = game.storageBytes, bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        guard let estimate = game.sizeEstimate,
              let bytes = estimate.installedBytes, bytes > 0 else { return "Unavailable" }
        let value = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return estimate.source.isExactManifest ? value : "≈ \(value)"
    }

    private var formattedCapacity: String {
        guard game.provider != .steam else { return "Shown by Steam" }
        guard let bytes = GameStorage.availableCapacity(at: capacityProbeURL) else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @ViewBuilder private var architectureSummary: some View {
        if game.supportsNativeMacOS != true {
            if let architecture = game.sizeEstimate?.executableArchitecture {
                let requiresWine = architecture == .x86
                Label(
                    requiresWine
                        ? "32-bit Windows game · Wine with WoW64 required"
                        : "64-bit Windows game · Wine or GPTK can be prepared",
                    systemImage: requiresWine ? "exclamationmark.shield.fill" : "checkmark.shield.fill"
                )
                .foregroundStyle(requiresWine ? .orange : .green)
                Text("Detected from store metadata before download. Boreal will verify the installed executable again before creating its runtime environment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Windows architecture unknown", systemImage: "questionmark.diamond")
                    .foregroundStyle(.secondary)
                Text("The store did not publish enough information to distinguish a 32-bit game from a 64-bit game. Boreal will inspect the executable after installation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var capacityProbeURL: URL {
        var candidate = destination
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    private func storageSummary(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.medium)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Game Installation Location"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        if panel.runModal() == .OK, let selected = panel.url {
            destination = selected.standardizedFileURL
        }
    }
}

private struct StoreScreenshotSelection: Identifiable {
    let urls: [URL]
    let initialIndex: Int
    var id: String { "\(urls.first?.absoluteString ?? "screenshots")#\(initialIndex)" }
}

private struct StoreScreenshotViewer: View {
    @Environment(\.dismiss) private var dismiss
    let screenshot: StoreScreenshotSelection
    let gameName: String
    @State private var currentIndex: Int

    init(screenshot: StoreScreenshotSelection, gameName: String) {
        self.screenshot = screenshot
        self.gameName = gameName
        _currentIndex = State(initialValue: min(max(screenshot.initialIndex, 0), max(screenshot.urls.count - 1, 0)))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(gameName).font(.title2).fontWeight(.semibold)
                Spacer()
                if screenshot.urls.count > 1 {
                    Text("\(currentIndex + 1) of \(screenshot.urls.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button("Close", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            ZStack {
                Color.black.opacity(0.88)
                if let url = currentURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else if phase.error != nil {
                            ContentUnavailableView("Screenshot Unavailable", systemImage: "photo.badge.exclamationmark")
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, screenshot.urls.count > 1 ? 72 : 18)
                    .padding(.vertical, 18)
                }
                if screenshot.urls.count > 1 {
                    HStack {
                        galleryButton(title: "Previous screenshot", symbol: "chevron.left", action: showPrevious)
                        Spacer()
                        galleryButton(title: "Next screenshot", symbol: "chevron.right", action: showNext)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.14)) }
        }
        .padding(22)
        .frame(minWidth: 1_280, idealWidth: 1_440, minHeight: 760, idealHeight: 900)
        .background(.ultraThinMaterial)
        .background {
            Button("Previous screenshot", action: showPrevious)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .hidden()
            Button("Next screenshot", action: showNext)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .hidden()
        }
    }

    private var currentURL: URL? {
        screenshot.urls.indices.contains(currentIndex) ? screenshot.urls[currentIndex] : nil
    }

    private func showPrevious() {
        guard !screenshot.urls.isEmpty else { return }
        currentIndex = (currentIndex - 1 + screenshot.urls.count) % screenshot.urls.count
    }

    private func showNext() {
        guard !screenshot.urls.isEmpty else { return }
        currentIndex = (currentIndex + 1) % screenshot.urls.count
    }

    private func galleryButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 48, height: 64)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct StoreVideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let video: StoreVideo
    @State private var player: AVPlayer

    init(video: StoreVideo) {
        self.video = video
        _player = State(initialValue: AVPlayer())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(video.name).font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            VideoPlayer(player: player)
                .frame(minWidth: 760, minHeight: 430)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.16)) }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .onAppear {
            guard let url = URL(string: video.videoURL) else { return }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }
        .onDisappear { player.pause() }
    }
}
