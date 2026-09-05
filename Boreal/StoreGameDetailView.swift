import AppKit
import AVKit
import Charts
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
    @State private var selectedMedia: StoreMediaSelection?
    @State private var showsUninstallConfirmation = false
    @State private var activityWidth: CGFloat = 0
    @State private var activityDayCount = 7
    @State private var selectedActivityDate: Date?
    @State private var showsActivityInfo = false
    @State private var selectedTab: DetailTab = .overview
    @State private var showsFullDescription = false
    @State private var compatibilityApplication: WindowsApplication?
    @State private var showsDiskStorageConfirmation = false
    @State private var diskStorageCategory: GameDiskStorageCategory?

    private var currentGame: StoreLibraryGame {
        store.storeGames.first {
            $0.provider == game.provider && $0.externalID == game.externalID
        } ?? game
    }

    var body: some View {
        GeometryReader { geometry in
            let hasRail = geometry.size.width >= 1080
            let inset: CGFloat = geometry.size.width < 600 ? 14 : 24
            let railWidth: CGFloat = 250
            let contentWidth = max(0, geometry.size.width - inset * 2 - (hasRail ? railWidth + 20 : 0))
            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(width: contentWidth)
                        detailTabBar
                        VStack(alignment: .leading, spacing: 12) {
                            if storeOperation != nil { operationStatus }
                            tabContent(width: contentWidth)
                            if !hasRail { detailsSidebar }
                        }
                        .padding(.top, 14)
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    if hasRail {
                        detailsSidebar.frame(width: railWidth)
                    }
                }
                .padding(.horizontal, inset)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(width: geometry.size.width, alignment: .topLeading)
            }
            .background {
                LinearGradient(
                    colors: [Color(red: 0.045, green: 0.08, blue: 0.12), Color(red: 0.025, green: 0.04, blue: 0.065)],
                    startPoint: .topTrailing, endPoint: .bottomLeading
                )
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: game.id) {
            selectedTab = .overview
            showsFullDescription = false
        }
        .onChange(of: visibleTabs) {
            if !visibleTabs.contains(selectedTab) { selectedTab = .overview }
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
        .task(id: diskReportTaskID) {
            store.refreshGameDiskStorage(for: currentGame)
        }
        .task(id: linkedEnvironment?.id) {
            if let environmentID = linkedEnvironment?.id {
                store.refreshDependencies(for: environmentID, application: linkedApplication)
            }
        }
        .task(id: game.id) {
            await store.loadStoreGameSizeIfNeeded(for: game.id)
        }
        .sheet(item: $selectedMedia) { selection in
            StoreMediaViewer(selection: selection, game: currentGame)
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
        .confirmationDialog("Clear \(diskStorageCategory?.title ?? "selected storage")?", isPresented: $showsDiskStorageConfirmation) {
            Button("Clear", role: .destructive) {
                if let category = diskStorageCategory { store.clearGameDiskStorage(category, for: currentGame) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes only data Boreal identified as disposable. Game files and the Windows prefix are not touched.")
        }
    }

    private func hero(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: width < 620 ? 16 : 24) {
                GameArtworkView(game: currentGame, width: width < 620 ? 82 : 124, height: width < 620 ? 116 : 174)
                VStack(alignment: .leading, spacing: 8) {
                    heroIdentity
                    if width >= 620 {
                        heroBadges
                        primaryActions.padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if width < 620 {
                heroBadges
                primaryActions
            }
        }
        .padding(width < 620 ? 16 : 20)
        .frame(maxWidth: .infinity, minHeight: 214, alignment: .leading)
        .background {
            GeometryReader { geometry in
                heroBackground
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.94), .black.opacity(0.72), .black.opacity(0.12)], startPoint: .leading, endPoint: .trailing)
                    }
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.13)) }
        .accessibilityElement(children: .contain)
    }

    private var heroIdentity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(linkedApplication?.usesStoreMetadataOnly == true ? "Custom Installed" : currentGame.provider.rawValue)  ·  IN YOUR LIBRARY")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Text(currentGame.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let developer = currentGame.developer {
                Button { onSelectProducer(developer) } label: {
                    Text(developer).font(.callout).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .help("Show all games by \(developer)")
            }
        }
    }

    private var heroBadges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { heroBadgeContent }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 6) { heroBadgeContent }
        }
    }

    @ViewBuilder private var heroBadgeContent: some View {
        if currentGame.supportsNativeMacOS != true {
            Label(compatibilityRating.rawValue + " compatibility", systemImage: compatibilityRating.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(compatibilityTint)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(compatibilityTint.opacity(0.12), in: Capsule())
        }
        StoreRatingBadge(rating: currentGame.storeRating)
        StorePlatformBadge(game: currentGame)
    }

    private var visibleTabs: [DetailTab] {
        DetailTab.allCases.filter { tab in
            switch tab {
            case .overview, .activity: true
            case .compatibility: currentGame.supportsNativeMacOS != true
            case .files: currentGame.installPath != nil || linkedApplication != nil
            }
        }
    }

    private var detailTabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 28) {
                ForEach(visibleTabs, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab.rawValue)
                            .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if selectedTab == tab { Capsule().fill(.blue).frame(height: 3) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private func tabContent(width: CGFloat) -> some View {
        switch selectedTab {
        case .overview:
            overviewMainColumn(width: width)
        case .compatibility:
            VStack(alignment: .leading, spacing: 12) {
                compatibilitySection
                if linkedEnvironment != nil { dependenciesSection }
            }
        case .activity:
            activitySection
        case .files:
            installationFilesSection
        }
    }

    private func overviewMainColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            libraryOverview(width: width)
            if currentGame.supportsNativeMacOS != true { compatibilityOverview(width: width) }
            mediaSection(width: width)
            overviewEditorialGrid(width: width)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dependenciesSection: some View {
        let environmentID = linkedEnvironment!.id
        let statuses = store.dependencyStatuses(for: environmentID, application: linkedApplication)
        let required = statuses.filter { $0.recommendation == .required }
        let recommended = statuses.filter { $0.recommendation == .recommended }
        let optional = statuses.filter { $0.recommendation == .optional }
        let canInstallRequired = required.contains { $0.state == .missing || $0.state == .failed }
        return detailCard("Dependencies", symbol: "shippingbox.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Boreal keeps this game’s prefix minimal and installs components only when they are required or you choose them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !required.isEmpty {
                    dependencyGroup("Required", statuses: required, environmentID: environmentID)
                }
                if !recommended.isEmpty {
                    dependencyGroup("Recommended for this game", statuses: recommended, environmentID: environmentID)
                }
                dependencyGroup("Optional", statuses: optional, environmentID: environmentID)
                if canInstallRequired {
                    Button("Install Required Dependencies", systemImage: "arrow.down.circle.fill") {
                        store.installRequiredDependencies(for: environmentID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(statuses.contains { $0.state == .installing })
                }
            }
        }
    }

    @ViewBuilder
    private func dependencyGroup(_ title: String, statuses: [RuntimeDependencyStatus], environmentID: UUID) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(statuses) { status in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: dependencySymbol(status.state))
                    .foregroundStyle(dependencyColor(status.state))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.dependency.displayName)
                    if let detail = status.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if status.state == .installing {
                    ProgressView().controlSize(.small)
                } else if status.state == .installed {
                    Text("Installed").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                } else {
                    Button(status.state == .failed ? "Retry" : "Install") {
                        store.installDependency(status.dependency, for: environmentID)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func dependencySymbol(_ state: RuntimeDependencyState) -> String {
        switch state {
        case .installed: "checkmark.circle.fill"
        case .missing: "circle"
        case .installing: "arrow.down.circle"
        case .failed: "xmark.circle.fill"
        }
    }

    private func dependencyColor(_ state: RuntimeDependencyState) -> Color {
        switch state {
        case .installed: .green
        case .missing: .secondary
        case .installing: .accentColor
        case .failed: .red
        }
    }

    private func overviewEditorialGrid(width: CGFloat) -> some View {
        let layout = width >= 880 ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
        return layout {
            aboutGameSection.frame(maxWidth: .infinity, alignment: .leading)
            gameSetupSection.frame(maxWidth: width >= 880 ? width * 0.4 : .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var gameSetupSection: some View {
        if let environment = linkedEnvironment, let application = linkedApplication {
            detailCard("Game setup", symbol: "gearshape.fill") {
                metric("Runtime", value: environment.runtime, symbol: "internaldrive")
                metric("Graphics", value: environment.graphics, symbol: "display")
                metric("Windows", value: environment.windowsVersion, symbol: "window.ceiling")
                let required = store.dependencyStatuses(for: environment.id, application: application).filter { $0.recommendation == .required }
                metric("Components", value: required.isEmpty ? "None required" : (required.allSatisfy { $0.state == .installed } ? "Ready" : "Requires attention"), symbol: "checkmark.circle")
                HStack(spacing: 10) {
                    Button("Configure") { compatibilityApplication = application }
                        .buttonStyle(BorealSecondaryActionButtonStyle())
                    Button("Components", systemImage: "arrow.right") { selectedTab = .compatibility }
                        .buttonStyle(BorealSecondaryActionButtonStyle())
                }
            }
        }
    }

    private var compatibilityRating: CompatibilityRating {
        currentGame.compatibility?.tier.rating ?? linkedApplication?.compatibility ?? .unknown
    }

    private var compatibilityTint: Color {
        switch compatibilityRating {
        case .excellent, .good: .mint
        case .limited: .orange
        case .unsupported: .red
        case .unknown: .secondary
        }
    }

    private func compatibilityOverview(width: CGFloat) -> some View {
        detailCard("Compatibility", symbol: "gamecontroller.fill") {
            let layout = width >= 1000 ? AnyLayout(HStackLayout(alignment: .center, spacing: 22)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            layout {
                let summaryLayout = width >= 1000 || width < 520 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
                summaryLayout {
                    HStack(spacing: 16) {
                        Image(systemName: compatibilityRating.symbol)
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(compatibilityTint)
                            .frame(width: 48, height: 48)
                            .background(compatibilityTint.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(compatibilityRating.rawValue + " compatibility")
                                .font(.system(size: 18, weight: .semibold))
                            Text(currentGame.compatibility == nil ? "No community reports available." : "Based on community compatibility reports.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if width < 1000 { compatibilityDetailsButton.frame(maxWidth: width >= 520 ? 140 : .infinity) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: width < 360 ? 1 : 2), alignment: .leading, spacing: 12) {
                    compatibilityFact("Graphics", value: linkedEnvironment?.graphics ?? "Not configured", symbol: "display")
                    compatibilityFact("Community", value: currentGame.compatibility.map { "\($0.reportCount.formatted()) reports · \($0.tier.title)" } ?? "No reports", symbol: "person.2.fill")
                }
                .frame(maxWidth: .infinity)
                if width >= 1000 { compatibilityDetailsButton.frame(width: 150) }
            }
        }
    }

    private var compatibilityDetailsButton: some View {
        Button("View details", systemImage: "arrow.right") { selectedTab = .compatibility }
            .buttonStyle(BorealSecondaryActionButtonStyle())
    }

    private func compatibilityFact(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.indigo.opacity(0.9))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aboutGameSection: some View {
        detailCard("About this game", symbol: "doc.text.fill") {
            if let summary = currentGame.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(2)
                    .lineLimit(showsFullDescription ? nil : 4)
                    .textSelection(.enabled)
                if summary.count > 160 {
                    Button(showsFullDescription ? "Show less" : "Read more") { showsFullDescription.toggle() }
                        .buttonStyle(.plain).foregroundStyle(.cyan).font(.caption.weight(.semibold))
                }
            } else {
                Text("No description provided by this store.").font(.callout).foregroundStyle(.secondary)
            }
            if let developer = currentGame.developer {
                Divider()
                metric("Developer", value: developer, symbol: "person.2")
            }
            metric("Source", value: currentGame.provider.rawValue, symbol: "bag")
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

    private var storeImageFailurePlaceholder: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var primaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                primaryLaunchAction
                secondaryHeroActions
            }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 10) {
                primaryLaunchAction
                secondaryHeroActions
            }
        }
        .tint(.blue)
    }

    @ViewBuilder private var primaryLaunchAction: some View {
            if let operation = storeOperation {
                storeOperationPrimaryButton(operation)
            } else if game.provider == .steam {
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
    }

    private var secondaryHeroActions: some View {
        HStack(spacing: 10) {
            Button {
                store.toggleFavorite(key: "\(currentGame.provider.rawValue):\(currentGame.externalID)")
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
            }
            .buttonStyle(BorealSquareActionButtonStyle())
            .foregroundStyle(isFavorite ? .purple : .secondary)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            moreActionsMenu
        }
    }

    private var isFavorite: Bool {
        store.isFavorite(key: "\(currentGame.provider.rawValue):\(currentGame.externalID)")
    }

    private var moreActionsMenu: some View {
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
        switch app.status {
        case .running:
            Button("Stop", systemImage: "stop.fill") { store.toggleRunning(app.id) }
                .buttonStyle(BorealPrimaryActionButtonStyle())
        case .preparing:
            primaryStatusButton("Preparing…", symbol: "gearshape.2.fill")
        case .starting:
            primaryStatusButton("Launching…", symbol: "play.circle.fill")
        case .installing:
            primaryStatusButton("Installing…", symbol: "shippingbox.fill")
        case .needsAttention:
            Button("Retry", systemImage: "arrow.clockwise") { store.retry(app.id) }
                .buttonStyle(BorealPrimaryActionButtonStyle())
        case .unavailable:
            primaryStatusButton("Unsupported", symbol: "xmark.octagon.fill")
        case .ready:
            Button(playTitle, systemImage: "play.fill") { store.toggleRunning(app.id) }
                .buttonStyle(BorealPrimaryActionButtonStyle())
        }
    }

    @ViewBuilder private func storeOperationPrimaryButton(_ operation: StoreGameOperationState) -> some View {
        switch operation {
        case .installing(let progress):
            primaryStatusButton(operationTitle(for: progress), symbol: operationSymbol(for: progress))
        case .preparingEnvironment:
            primaryStatusButton("Preparing…", symbol: "gearshape.2.fill")
        case .paused:
            Button("Queued", systemImage: "clock.fill") { store.resumeStoreGameOperation(currentGame) }
                .buttonStyle(BorealPrimaryActionButtonStyle())
                .help("Resume installation")
        case .awaitingProvider:
            primaryStatusButton("Queued", symbol: "clock.fill")
        case .failed:
            Button("Retry", systemImage: "arrow.clockwise") {
                if store.canResumeStoreGameOperation(currentGame) {
                    store.resumeStoreGameOperation(currentGame)
                } else {
                    store.clearStoreGameOperation(for: currentGame)
                    showsInstallationOptions = true
                }
            }
            .buttonStyle(BorealPrimaryActionButtonStyle())
        }
    }

    private func primaryStatusButton(_ title: String, symbol: String) -> some View {
        Button(title, systemImage: symbol) { }
            .buttonStyle(BorealPrimaryActionButtonStyle())
            .disabled(true)
    }

    private func operationTitle(for progress: StoreGameOperationProgress) -> String {
        let base: String
        if currentGame.isInstalled {
            base = progress.phase == .verifying ? "Repairing" : "Updating"
        } else {
            switch progress.phase {
            case .preparing: base = "Preparing"
            case .downloading: base = "Downloading"
            case .installing: base = "Installing"
            case .verifying: base = "Finishing"
            }
        }
        if let fraction = progress.clampedFraction {
            return "\(base)… \(Int((fraction * 100).rounded()))%"
        }
        return "\(base)…"
    }

    private func operationSymbol(for progress: StoreGameOperationProgress) -> String {
        switch progress.phase {
        case .preparing: "gearshape.2.fill"
        case .downloading: "arrow.down.circle.fill"
        case .installing: "shippingbox.fill"
        case .verifying: "checkmark.shield.fill"
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
        let providerSeconds = TimeInterval(currentGame.playtimeMinutes * 60)
        let activeSeconds = store.activePlaySessionElapsed(for: currentGame) ?? 0
        let completedMeasuredSeconds = currentGame.completedPlaySessions.reduce(0) { $0 + $1.duration }
        let totalSeconds = activeSeconds > 0
            ? max(providerSeconds, completedMeasuredSeconds) + activeSeconds
            : max(providerSeconds, currentGame.measuredPlaytime)
        guard totalSeconds > 0 else { return "Not played" }
        return formatDuration(totalSeconds)
    }

    private func libraryOverview(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: width >= 760 ? 4 : (width >= 360 ? 2 : 1)), spacing: 12) {
                overviewMetric("Playtime", value: playtime, symbol: "clock")
                overviewMetric("Last played", value: lastPlayedValue, symbol: "calendar")
                overviewMetric(requiredStorageTitle, value: formattedRequiredStorage, symbol: "internaldrive")
                overviewMetric("Compatibility", value: currentGame.supportsNativeMacOS == true ? "Native macOS" : compatibilityRating.rawValue, symbol: compatibilityRating.symbol, tint: currentGame.supportsNativeMacOS == true ? .mint : compatibilityTint)
            }
        }
    }

    private var lastPlayedValue: String {
        if store.activePlaySessionStart(for: currentGame) != nil { return "Playing now" }
        return currentGame.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
    }

    private var activitySection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            activityDashboard(at: context.date)
        }
    }

    private func activityDashboard(at date: Date) -> some View {
        let sessions = activitySessions
        let statistics = GameActivityStatistics(sessions: sessions, now: date, heatmapDayCount: max(84, activityDayCount))
        let columns = activityWidth >= 900 ? 5 : (activityWidth >= 560 ? 3 : (activityWidth >= 350 ? 2 : 1))
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                activityMetric("Total playtime", value: formatDuration(sessions.reduce(0) { $0 + $1.duration }), symbol: "clock")
                activityMetric("Sessions", value: "\(sessions.count)", symbol: "gamecontroller")
                activityMetric("Average session", value: formatDuration(statistics.averageSession), symbol: "chart.bar.fill")
                activityMetric("Longest session", value: formatDuration(statistics.longestSession), symbol: "trophy")
                activityMetric("Last played", value: lastPlayedValue, symbol: "calendar", subtitle: currentGame.lastPlayed.map { $0.formatted(.relative(presentation: .named)) })
            }
            if activityWidth >= 760 {
                HStack(alignment: .top, spacing: 12) {
                    activityTrackingCard.frame(width: (activityWidth - 12) * 0.56)
                    activityWeekCard(statistics, at: date)
                }
            } else {
                activityTrackingCard
                activityWeekCard(statistics, at: date)
            }
            if activityWidth >= 900 {
                HStack(alignment: .top, spacing: 12) {
                    activityChart(statistics).frame(width: (activityWidth - 12) * 0.62)
                    activityHeatmap(statistics)
                }
            } else {
                activityChart(statistics)
                activityHeatmap(statistics)
            }
            activityHistory(sessions)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { activityWidth = $0 }
    }

    private func activityMetric(_ title: String, value: String, symbol: String, subtitle: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.85)
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.09)) }
    }

    private var activityTrackingCard: some View {
        activityCard("Tracked by Boreal", symbol: "info.circle.fill", minimumHeight: 100) {
            HStack(spacing: 16) {
                Text("Activity is measured while \(currentGame.name) is launched through Boreal. Offline play and other launchers may not be included.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Learn more") { showsActivityInfo = true }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.06)) }
                    .fixedSize()
                    .popover(isPresented: $showsActivityInfo) {
                        Text("Boreal records elapsed time while a managed game session is active. These statistics use locally recorded sessions; store-reported playtime can differ. Sessions interrupted when Boreal closes may be incomplete.")
                            .font(.callout).padding(20).frame(width: 320)
                    }
            }
        }
    }

    private func activityWeekCard(_ statistics: GameActivityStatistics, at date: Date) -> some View {
        activityCard("This week", symbol: "calendar.badge.clock", minimumHeight: 100) {
            HStack(alignment: .top) {
                if let week = Calendar.autoupdatingCurrent.dateInterval(of: .weekOfYear, for: date) {
                    Text("\(week.start.formatted(.dateTime.day().month())) – \(week.end.addingTimeInterval(-1).formatted(.dateTime.day().month().year()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(formatDuration(statistics.thisWeek)).font(.headline).monospacedDigit()
                        if statistics.lastWeek > 0 {
                            let change = (statistics.thisWeek - statistics.lastWeek) / statistics.lastWeek
                            Text(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always())))
                                .font(.caption).foregroundStyle(change >= 0 ? .green : .secondary)
                        }
                    }
                    Text("Last week: \(formatDuration(statistics.lastWeek))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func activityChart(_ statistics: GameActivityStatistics) -> some View {
        let days = Array(statistics.days.suffix(activityDayCount))
        return activityCard("Playtime over time", symbol: "chart.xyaxis.line", minimumHeight: 180, showsPeriod: true) {
            Chart(days) { day in
                AreaMark(x: .value("Date", day.date), y: .value("Minutes", day.duration / 60))
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.3), .blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", day.date), y: .value("Minutes", day.duration / 60))
                    .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2))
                if activityDayCount == 7 {
                    PointMark(x: .value("Date", day.date), y: .value("Minutes", day.duration / 60))
                        .foregroundStyle(.blue).symbolSize(28)
                }
                if let selection = selectedActivityDate,
                   Calendar.autoupdatingCurrent.isDate(day.date, inSameDayAs: selection) {
                    RuleMark(x: .value("Selected date", day.date))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(formatDuration(day.duration)).fontWeight(.semibold)
                                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                            }
                            .font(.caption).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        }
                }
            }
            .chartXSelection(value: $selectedActivityDate)
            .chartYScale(domain: 0...max(1, (days.map(\.duration).max() ?? 0) / 60 * 1.12))
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let plotFrame = proxy.plotFrame {
                                // Chart coordinates are relative to the plot, not the full card.
                                selectedActivityDate = proxy.value(atX: location.x - geometry[plotFrame].minX, as: Date.self)
                            }
                        case .ended: selectedActivityDate = nil
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel { if let minutes = value.as(Double.self) { Text("\(minutes.formatted(.number.precision(.fractionLength(0)))) min") } }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
            .frame(height: 126)
            .onChange(of: activityDayCount) { selectedActivityDate = nil }
        }
    }

    private func activityHeatmap(_ statistics: GameActivityStatistics) -> some View {
        let days = Array(statistics.days.suffix(84))
        let maximum = days.map(\.duration).max() ?? 0
        return activityCard("Activity heatmap", symbol: "square.grid.3x3.fill", minimumHeight: 180) {
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 8) {
                    HStack {
                        Text(days.first?.date.formatted(.dateTime.month(.abbreviated)) ?? "")
                        Spacer()
                        Text(days[days.count / 2].date.formatted(.dateTime.month(.abbreviated)))
                        Spacer()
                        Text(days.last?.date.formatted(.dateTime.month(.abbreviated)) ?? "")
                    }.font(.caption2).foregroundStyle(.secondary)
                    // Twelve columns represent consecutive weeks, read top to bottom.
                    HStack(spacing: 3) {
                        ForEach(0..<12, id: \.self) { week in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { weekday in
                                    let day = days[week * 7 + weekday]
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(heatmapColor(for: day.duration, maximum: maximum))
                                        .frame(maxWidth: .infinity).frame(height: 12)
                                        .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(formatDuration(day.duration))")
                                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                                        .accessibilityValue(formatDuration(day.duration))
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach([4, 2, 1, 0], id: \.self) { level in
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 2).fill(heatmapColor(for: Double(level), maximum: 4)).frame(width: 10, height: 10)
                            Text(["No activity", "A little activity", "Some activity", "", "More activity"][level])
                        }
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
            }
            .frame(height: 126)
        }
    }

    private func activityHistory(_ sessions: [GamePlaySession]) -> some View {
        activityCard("Session history", symbol: "list.bullet.rectangle", sessionCount: sessions.count) {
            if sessions.isEmpty {
                Text("No sessions recorded yet. Launch this game through Boreal to start tracking activity.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 18)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                        GridRow {
                            Text("Date").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Start time").frame(maxWidth: .infinity, alignment: .leading)
                            Text("End time").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Duration").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Status").frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.caption2).foregroundStyle(.secondary)
                        ForEach(sessions.sorted { $0.startedAt > $1.startedAt }) { session in
                            Divider().gridCellUnsizedAxes(.horizontal)
                            GridRow {
                                HStack(spacing: 9) {
                                    Circle().fill(session.isActive ? .blue : .green).frame(width: 7, height: 7)
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                                }
                                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                                Text(session.endedAt?.formatted(date: .omitted, time: .shortened) ?? "—")
                                Text(formatDuration(session.duration)).monospacedDigit()
                                Text(session.isActive ? "Playing now" : "Completed")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(session.isActive ? .blue : .green)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background((session.isActive ? Color.blue : Color.green).opacity(0.12), in: Capsule())
                            }.font(.caption)
                        }
                    }.frame(width: max(560, activityWidth - 28), alignment: .leading)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private func activityCard<Content: View>(
        _ title: String, symbol: String, minimumHeight: CGFloat = 0,
        showsPeriod: Bool = false, sessionCount: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(symbol == "info.circle.fill" ? Color.cyan : Color.primary.opacity(0.9))
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if showsPeriod {
                    HStack(spacing: 3) {
                        ForEach([7, 30, 90, 365], id: \.self) { days in
                            Button { activityDayCount = days } label: {
                                Text(days == 365 ? "1Y" : "\(days)D")
                                    .font(.system(size: 10, weight: .medium))
                                    .frame(width: activityWidth < 430 ? 29 : 39, height: 24)
                                    .background(activityDayCount == days ? Color.blue : .clear, in: Capsule())
                                    .foregroundStyle(activityDayCount == days ? .white : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(days == 365 ? "1 year" : "\(days) days")
                            .accessibilityAddTraits(activityDayCount == days ? .isSelected : [])
                        }
                    }
                    .padding(3).background(.white.opacity(0.04), in: Capsule())
                }
                if let sessionCount {
                    Text("\(sessionCount) sessions").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 30)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.09)) }
    }

    private var activitySessions: [GamePlaySession] {
        var sessions = currentGame.completedPlaySessions
        if var active = currentGame.activePlaySession,
           let elapsed = store.activePlaySessionElapsed(for: currentGame) {
            active.measuredDurationSeconds = elapsed
            sessions.append(active)
        }
        return sessions
    }

    private func heatmapColor(for duration: TimeInterval, maximum: TimeInterval) -> Color {
        guard duration > 0, maximum > 0 else { return .secondary.opacity(0.12) }
        let level = min(1, max(0.2, duration / maximum))
        return .blue.opacity(0.25 + level * 0.75)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        if minutes > 0 { return "\(minutes) min" }
        return "\(seconds) sec"
    }

    private func overviewMetric(_ title: String, value: String, symbol: String, tint: Color = .blue) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(title == "Compatibility" ? tint : .primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)) }
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
              let bytes = estimate.installedBytes, bytes > 0 else { return "Not provided" }
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

    @ViewBuilder private func mediaSection(width: CGFloat) -> some View {
        let screenshots = currentGame.screenshotURLs ?? []
        let videos = currentGame.videos ?? []
        let galleryURLs = screenshots.compactMap(URL.init(string:))
        let mediaItems = galleryURLs.map(StoreMediaItem.screenshot) + videos.map(StoreMediaItem.video)
        let visibleCount: CGFloat = width >= 1150 ? 5 : (width >= 850 ? 4 : (width >= 620 ? 3 : 2))
        let thumbnailWidth = max(156, (width - 28 - (visibleCount - 1) * 10) / visibleCount)
        if !mediaItems.isEmpty {
            detailCard("Media", symbol: "photo", actionTitle: "View all media", action: {
                selectedMedia = StoreMediaSelection(items: mediaItems, initialIndex: 0)
            }) {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                            Button {
                                selectedMedia = StoreMediaSelection(items: mediaItems, initialIndex: index)
                            } label: {
                                mediaThumbnail(item, width: thumbnailWidth)
                            }
                            .buttonStyle(.plain)
                            .help(item.isVideo ? item.accessibilityTitle : "Open screenshot \(index + 1)")
                            .accessibilityLabel(item.isVideo ? item.accessibilityTitle : "Open screenshot \(index + 1) of \(mediaItems.count)")
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private func mediaThumbnail(_ item: StoreMediaItem, width: CGFloat) -> some View {
        StoreMediaThumbnail(item: item, width: width)
    }

    private var detailsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if currentGame.installPath != nil || currentGame.storageBytes != nil || currentGame.sizeEstimate != nil {
                detailCard("Installation", symbol: "internaldrive.fill") {
                    Label(currentGame.isInstalled || linkedApplication != nil ? "Installed" : "Not installed", systemImage: currentGame.isInstalled || linkedApplication != nil ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(currentGame.isInstalled || linkedApplication != nil ? Color.mint : Color.secondary)
                    Divider()
                    metric(requiredStorageTitle, value: formattedRequiredStorage, symbol: "internaldrive")
                    if let environment = linkedEnvironment {
                        metric("Prefix", value: store.formattedBytes(environment.storageBytes), symbol: "shippingbox")
                    }
                    if currentGame.installPath != nil {
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Location").font(.caption).foregroundStyle(.secondary)
                            Text(installationLocation).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                                .help(currentGame.installPath ?? installationLocation)
                        }
                    }
                    if currentGame.sizeEstimate?.downloadBytes != nil {
                        metric("Download", value: formattedDownloadSize, symbol: "arrow.down.circle")
                    }
                    if currentGame.installPath != nil {
                        Button("Manage files", systemImage: "arrow.right") { selectedTab = .files }
                            .buttonStyle(BorealSecondaryActionButtonStyle())
                    }
                }
            }
            if let environment = linkedEnvironment {
                detailCard("Environment", symbol: "shippingbox") {
                    metric("Runtime", value: environment.runtime, symbol: "gearshape.2")
                    metric("Graphics", value: environment.graphics, symbol: "display")
                    metric("Windows version", value: environment.windowsVersion, symbol: "window.ceiling")
                    metric("Architecture", value: environment.architecture, symbol: "cpu")
                    if let application = linkedApplication {
                        Button("Configure", systemImage: "arrow.right") { compatibilityApplication = application }
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
            diskStorageCard
        }
    }

    private var diskStorageCard: some View {
        let report = store.gameDiskReport(for: currentGame)
        return detailCard("Disk usage", symbol: "internaldrive.fill") {
            ForEach(GameDiskStorageCategory.allCases, id: \.self) { category in
                let item = report?.item(category)
                metric(category.title, value: item?.bytes.map(store.formattedBytes) ?? "Unavailable", symbol: category == .shaders ? "sparkles" : "internaldrive")
            }
            Divider()
            Text("Shader Cache").font(.subheadline.weight(.semibold))
            HStack {
                Text("Cache may rebuild during gameplay. Temporary stutter is expected.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { diskStorageCategory = .shaders; showsDiskStorageConfirmation = true }
                    .disabled(report?.item(.shaders)?.bytes == nil)
                Button("Rebuild") { store.rebuildShaderCache(for: currentGame) }
                    .disabled(report?.item(.shaders)?.bytes == nil)
            }
            .buttonStyle(.bordered)
            HStack {
                clearButton(.downloads, title: "Remove Downloads", report: report)
                clearButton(.snapshots, title: "Delete Old Snapshots", report: report)
            }
        }
    }

    private func clearButton(_ category: GameDiskStorageCategory, title: String, report: GameDiskStorageReport?) -> some View {
        Button(title) { diskStorageCategory = category; showsDiskStorageConfirmation = true }
            .disabled(report?.item(category)?.bytes == nil)
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

    private var cardFill: LinearGradient {
        LinearGradient(colors: [Color(red: 0.09, green: 0.125, blue: 0.18), Color(red: 0.065, green: 0.095, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func detailCard<Content: View>(_ title: String, symbol: String, actionTitle: String? = nil, action: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer(minLength: 8)
                if let actionTitle {
                    Button(actionTitle, systemImage: "arrow.right", action: action)
                        .font(.caption.weight(.medium)).buttonStyle(.plain).foregroundStyle(.cyan)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.13)) }
    }

    private var linkedApplication: WindowsApplication? { store.linkedApplication(for: game) }

    private var diskReportTaskID: String {
        "disk-\(game.id.uuidString)-\(currentGame.installPath ?? "uninstalled")"
    }

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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.14)) }
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
        HStack(alignment: .top, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(value).font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing).textSelection(.enabled)
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
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(.cyan)
            .background(.blue.opacity(configuration.isPressed ? 0.28 : (isHovered ? 0.2 : 0.12)))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.blue.opacity(0.35))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }
}

private struct BorealPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 132, minHeight: 40)
            .padding(.horizontal, 4)
            .background(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [Color.blue.opacity(0.85), Color.blue.opacity(0.7)]
                        : [Color(red: 0.02, green: 0.58, blue: 1), Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .blue.opacity(0.28), radius: 8, y: 3)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct BorealSquareActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
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
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(.white.opacity(isHovered && isEnabled ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
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

private enum StoreMediaItem: Hashable, Identifiable {
    case screenshot(URL)
    case video(StoreVideo)

    var id: String {
        switch self {
        case .screenshot(let url): "screenshot:\(url.absoluteString)"
        case .video(let video): "video:\(video.id)"
        }
    }

    var thumbnailURL: URL? {
        switch self {
        case .screenshot(let url): url
        case .video(let video): video.thumbnailURL.flatMap(URL.init(string:))
        }
    }

    var title: String {
        switch self {
        case .screenshot: "Screenshot"
        case .video(let video): video.name
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .screenshot: "Open screenshot"
        case .video(let video): "Play \(video.name)"
        }
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

private struct StoreMediaSelection: Identifiable {
    let items: [StoreMediaItem]
    let initialIndex: Int
    var id: String { "\(items.map(\.id).joined(separator: "|"))#\(initialIndex)" }
}

private struct StoreMediaThumbnail: View {
    let item: StoreMediaItem
    let width: CGFloat

    var body: some View {
        ZStack {
            if let url = item.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    case .empty: Rectangle().fill(.background.secondary).overlay { ProgressView() }
                    @unknown default: Rectangle().fill(.background.secondary)
                    }
                }
            } else {
                placeholder
            }
            if item.isVideo {
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: width, height: width * 0.46)
        .overlay(alignment: .bottomLeading) {
            if item.isVideo {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }
}

private struct StoreMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    let selection: StoreMediaSelection
    let game: StoreLibraryGame
    @State private var currentIndex: Int
    @State private var player = AVPlayer()
    @State private var isPlaying = false

    init(selection: StoreMediaSelection, game: StoreLibraryGame) {
        self.selection = selection
        self.game = game
        _currentIndex = State(initialValue: min(max(selection.initialIndex, 0), max(selection.items.count - 1, 0)))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            mediaStage
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            metadata
            Divider().opacity(0.6)
            filmstrip
        }
        .frame(minWidth: 860, idealWidth: 1_080, minHeight: 620, idealHeight: 760)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
        .onAppear(perform: preparePlayer)
        .onChange(of: currentIndex) { preparePlayer() }
        .onDisappear { player.pause() }
        .onExitCommand { dismiss() }
        .background {
            Button("Previous media", action: showPrevious)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .hidden()
            Button("Next media", action: showNext)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .hidden()
            Button("Play or pause video", action: togglePlayback)
                .keyboardShortcut(.space, modifiers: [])
                .hidden()
            Button("Toggle fullscreen", action: toggleFullscreen)
                .keyboardShortcut(.return, modifiers: [.command])
                .hidden()
            Button("Toggle fullscreen", action: toggleFullscreen)
                .keyboardShortcut("f", modifiers: [])
                .hidden()
        }
    }

    private var currentItem: StoreMediaItem {
        guard selection.items.indices.contains(currentIndex) else {
            return selection.items.first ?? .screenshot(URL(fileURLWithPath: "/"))
        }
        return selection.items[currentIndex]
    }

    private var header: some View {
        HStack(spacing: 12) {
            GameArtworkView(game: game, width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).font(.headline)
                Text("Media").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Text("\(currentIndex + 1) / \(selection.items.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button(action: toggleFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Fullscreen (⌘↩)")
            .accessibilityLabel("Fullscreen")
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var mediaStage: some View {
        ZStack {
            mediaBackdrop
            mediaContent
            if selection.items.count > 1 {
                HStack {
                    galleryButton(title: "Previous media", symbol: "chevron.left", action: showPrevious)
                    Spacer()
                    galleryButton(title: "Next media", symbol: "chevron.right", action: showNext)
                }
                .padding(.horizontal, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.14)) }
    }

    @ViewBuilder private var mediaBackdrop: some View {
        if let url = currentItem.thumbnailURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.black
                }
            }
            .scaleEffect(1.15)
            .blur(radius: 30)
            .overlay(Color.black.opacity(0.56))
        } else {
            Color.black
        }
    }

    @ViewBuilder private var mediaContent: some View {
        switch currentItem {
        case .screenshot(let url):
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
        case .video:
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var metadata: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(currentItem.title) \(currentIndex + 1) of \(selection.items.count)")
                    .font(.subheadline.weight(.semibold))
                Text(currentItem.isVideo ? "Video" : "Screenshot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if currentItem.isVideo {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    private var filmstrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(selection.items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        currentIndex = index
                    } label: {
                        StoreMediaThumbnail(item: item, width: 142)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(index == currentIndex ? Color.accentColor : .white.opacity(0.12), lineWidth: index == currentIndex ? 3 : 1)
                            }
                            .opacity(index == currentIndex ? 1 : 0.72)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.accessibilityTitle)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.automatic)
    }

    private func preparePlayer() {
        player.pause()
        isPlaying = false
        guard case .video(let video) = currentItem, let url = URL(string: video.videoURL) else {
            player.replaceCurrentItem(with: nil)
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        isPlaying = true
    }

    private func togglePlayback() {
        guard currentItem.isVideo else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func toggleFullscreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }

    private func showPrevious() {
        guard !selection.items.isEmpty else { return }
        currentIndex = (currentIndex - 1 + selection.items.count) % selection.items.count
    }

    private func showNext() {
        guard !selection.items.isEmpty else { return }
        currentIndex = (currentIndex + 1) % selection.items.count
    }

    private func galleryButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.2)) }
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
