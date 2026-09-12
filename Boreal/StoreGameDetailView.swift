import AppKit
import AVKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct StoreGameDetailView: View {
    private enum DetailTab: String, CaseIterable {
        case overview
        case compatibility
        case offers
        case activity
        case files

        var title: LocalizedStringResource {
            switch self {
            case .overview: .Library.overviewTab
            case .compatibility: .Library.compatibilityTab
            case .offers: .Library.offersTab
            case .activity: .Library.activityTab
            case .files: .Library.filesTab
            }
        }
    }

    @Environment(BorealStore.self) private var store
    @AppStorage(ITADPriceService.apiKeyDefaultsKey) private var itadAPIKey = ""
    @AppStorage(ITADPriceService.countryCodeDefaultsKey) private var itadCountryCode = "PL"
    let game: StoreLibraryGame
    var discoveryGame: AppleGamingWikiGame? = nil
    var onSelectProducer: (String) -> Void = { _ in }
    @State private var showsInstallationOptions = false
    @State private var showsProgressDetails = false
    @State private var selectedMedia: StoreMediaSelection?
    @State private var showsUninstallConfirmation = false
    @State private var showsDLSSUnlockerUninstallConfirmation = false
    @State private var activityWidth: CGFloat = 0
    @State private var activityDayCount = 7
    @State private var selectedActivityDate: Date?
    @State private var showsActivityInfo = false
    @State private var selectedTab: DetailTab = .overview
    @State private var showsFullDescription = false
    @State private var compatibilityApplication: WindowsApplication?
    @State private var showsDiskStorageConfirmation = false
    @State private var diskStorageCategory: GameDiskStorageCategory?
    @State private var showsRenameDialog = false
    @State private var renameValue = ""
    @State private var customApplicationID: UUID?
    @State private var coverEditorState: StoreGameCoverEditorState?
    @State private var priceHistoryRange: DiscoveryPriceHistoryRange = .threeMonths
    @State private var priceHistory: [ITADPriceHistoryPoint] = []
    @State private var priceHistoryLoading = false

    private var currentGame: StoreLibraryGame {
        let linkedGame: StoreLibraryGame? = linkedApplication.flatMap { application in
            guard let provider = application.storeProvider,
                  let externalID = application.storeExternalID else { return nil }
            return store.storeGames.first { $0.provider == provider && $0.externalID == externalID }
        }
        var value = linkedGame ?? store.storeGames.first {
            $0.provider == game.provider && $0.externalID == game.externalID
        } ?? game
        if let application = linkedApplication, application.usesStoreMetadataOnly {
            value.name = application.name
        }
        return value
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
                            if currentGame.resolvedEntitlementState == .accountDisconnected {
                                entitlementDisconnectedNotice
                            }
                            if store.installation(for: currentGame)?.state == .volumeUnavailable {
                                volumeUnavailableNotice
                            }
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
        .id(currentGame.storeReference)
        .preferredColorScheme(.dark)
        .onAppear {
            customApplicationID = store.linkedApplication(for: game)?.id
        }
        .onChange(of: game.id) {
            selectedTab = .overview
            showsFullDescription = false
            priceHistory = []
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
        .task(id: "compatibility-preparation-\(game.id.uuidString)-\(store.isInstalled(currentGame))-\(linkedApplication?.id.uuidString ?? "none")") {
            guard [.epic, .gog].contains(game.provider),
                  currentGame.resolvedEntitlementState.isUsable,
                  store.usesManagedRuntime(for: currentGame),
                  store.isInstalled(currentGame),
                  linkedApplication == nil,
                  store.storeGameOperation(for: currentGame) == nil else { return }
            store.prepareStoreGame(currentGame)
        }
        .task(id: game.id) {
            await store.loadStoreGameSizeIfNeeded(for: game.id)
        }
        .sheet(item: $compatibilityApplication) { application in
            WineCompatibilityConfigurator(application: store.application(id: application.id) ?? application)
        }
        .sheet(item: $selectedMedia) { selection in
            StoreMediaViewer(selection: selection, game: currentGame) {
                selectedMedia = nil
            }
            .frame(minWidth: 960, minHeight: 800)
            .presentationBackground(.clear)
        }
        .sheet(item: $coverEditorState) { state in
            CustomCoverEditorView(
                title: currentGame.name,
                sourceLabel: currentGame.provider.rawValue,
                statusLabel: currentGame.isInstalled ? String(localized: .Library.installed) : String(localized: .Library.notInstalled),
                sourceData: state.sourceData,
                initialCrop: state.crop,
                onCancel: { coverEditorState = nil },
                onSave: { originalData, renderedData, crop in
                    store.saveCustomArtwork(
                        originalData: originalData,
                        renderedData: renderedData,
                        crop: crop,
                        forStoreGameID: state.gameID
                    )
                    coverEditorState = nil
                }
            )
        }
        .task(id: game.id) {
            store.refreshSteamMetadataIfNeeded(for: game)
        }
        .task(id: "steam-fallback-\(game.id.uuidString)") {
            store.refreshSteamPresentationFallbackIfNeeded(for: game)
        }
        .task(id: "gog-revived-\(game.id.uuidString)") {
            guard let discoveryGame else { return }
            await store.ensureGOGRevivedAvailability(for: discoveryGame)
        }
        .task(id: game.id) {
            await store.loadSteamCurrentPlayerCountIfNeeded(for: game.id)
        }
        .task(id: "\(game.id)-itad-\(itadAPIKey)-\(itadCountryCode)") {
            if let discoveryGame {
                await store.ensureDiscoveryPrice(for: discoveryGame)
            }
        }
        .task(id: "\(game.id)-offers-\(selectedTab.rawValue)-\(priceHistoryRange.rawValue)-\(itadAPIKey)-\(itadCountryCode)") {
            guard selectedTab == .offers, let discoveryGame else { return }
            await store.ensureDiscoveryOffers(for: discoveryGame)
            priceHistoryLoading = true
            priceHistory = await store.loadDiscoveryPriceHistory(for: discoveryGame, since: priceHistoryRange.since) ?? []
            priceHistoryLoading = false
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
        .confirmationDialog("Remove GTA SA DLSS Unlocker?", isPresented: $showsDLSSUnlockerUninstallConfirmation) {
            Button("Remove Unlocker", role: .destructive) {
                if let application = linkedApplication {
                    store.uninstallDLSSUnlocker(for: application.id)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Boreal will disable the signature override and restore the original DLLs saved before installation.")
        }
        .alert("Rename Game", isPresented: $showsRenameDialog) {
            TextField("Game name", text: $renameValue)
            Button("Cancel", role: .cancel) { renameValue = "" }
            Button("Rename") {
                if let application = linkedApplication {
                    customApplicationID = application.id
                    store.renameCustomApplication(application.id, to: renameValue)
                }
                renameValue = ""
            }
            .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Boreal will search Steam, Epic Games and GOG for artwork, description and other game details.")
        }
    }

    private var entitlementDisconnectedNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Store account disconnected")
                    .font(.callout.weight(.semibold))
                Text(store.installation(for: currentGame)?.state.representsAnInstallation == true
                    ? "The local installation and its play history were kept. Reconnect the account to install, update, or verify this game."
                    : "The entitlement is unavailable until this store account is connected again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.orange)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange.opacity(0.25)) }
    }

    private var volumeUnavailableNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Installation volume unavailable")
                    .font(.callout.weight(.semibold))
                Text("Boreal found the saved installation identity, but the volume is not mounted. Connect the disk before launching or managing this installation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "externaldrive.badge.xmark")
                .foregroundStyle(.orange)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange.opacity(0.25)) }
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
            HStack(spacing: 4) {
                if discoveryGame == nil {
                    if linkedApplication?.usesStoreMetadataOnly == true {
                        Text(.Library.importedGames)
                    } else {
                        Text(currentGame.provider.rawValue)
                    }
                    Text("·")
                    Text(.Library.inYourLibrary)
                } else {
                    Text(currentGame.provider.rawValue)
                    Text("·")
                    Text(.Library.discoveryLabel)
                }
            }
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
            Label {
                HStack(spacing: 4) {
                    Text(compatibilityRating.localizedTitle)
                    Text(.Library.compatibilityLabel)
                }
            } icon: {
                Image(systemName: compatibilityRating.symbol)
            }
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
            case .overview: true
            case .offers: discoveryGame != nil
            case .activity: discoveryGame == nil
            case .compatibility: currentGame.supportsNativeMacOS != true
            case .files: store.installedLocation(for: currentGame) != nil || linkedApplication != nil
            }
        }
    }

    private var detailTabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 28) {
                ForEach(visibleTabs, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab.title)
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
        case .offers:
            discoveryOffersSection
        case .activity:
            activitySection
        case .files:
            installationFilesSection
        }
    }

    @ViewBuilder private func overviewMainColumn(width: CGFloat) -> some View {
        if discoveryGame != nil {
            discoveryOverview(width: width)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                libraryOverview(width: width)
                if currentGame.supportsNativeMacOS != true { compatibilityOverview(width: width) }
                mediaSection(width: width)
                overviewEditorialGrid(width: width)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func discoveryOverview(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            discoveryPriceCard
            if currentGame.supportsNativeMacOS != true { compatibilityOverview(width: width) }
            mediaSection(width: width)
            overviewEditorialGrid(width: width)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var discoveryPriceCard: some View {
        if let discoveryGame {
            detailCard(.Library.priceTitle, symbol: "tag.fill", actionTitle: .Library.viewOffers, action: { selectedTab = .offers }) {
                if let summary = store.discoveryPriceSummary(for: discoveryGame) {
                    if let offer = summary.bestOffer {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(offer.price.formatted)
                                .font(.system(size: 24, weight: .bold))
                            if let discount = offer.discountLabel {
                                Text(discount)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(.green.opacity(0.12), in: Capsule())
                            }
                            Spacer()
                            Text(offer.shop.name).font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(.Library.noCurrentOffers).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        if let low = summary.historicalLow {
                            Label {
                                HStack(spacing: 4) {
                                    Text(.Library.lowPrice)
                                    Text(low.price.formatted)
                                }
                            } icon: {
                                Image(systemName: "chart.line.downtrend.xyaxis")
                            }
                        }
                        if let quality = summary.dealQuality {
                            Label(quality.title, systemImage: quality.symbol).foregroundStyle(quality == .poor ? .orange : .green)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                } else if store.isDiscoveryPriceLoading(for: discoveryGame) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(.Library.loadingCurrentOffers)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text(ITADPriceService.isConfigured ? .Library.priceDataUnavailable : .Library.priceAPIKeyForPrices)
                        .foregroundStyle(.secondary)
                }
                Text(.Library.pricesByItad)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder private var discoveryOffersSection: some View {
        if let discoveryGame {
            let summary = store.discoveryPriceSummary(for: discoveryGame)
            VStack(alignment: .leading, spacing: 12) {
                detailCard(.Library.offersTitle, symbol: "tag.fill") {
                    if let summary {
                        if let offer = summary.bestOffer {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(.Library.bestPrice).font(.caption).foregroundStyle(.secondary)
                                    Text(offer.price.formatted).font(.title2.bold())
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(offer.shop.name).font(.callout.weight(.semibold))
                                    if let quality = summary.dealQuality {
                                        Label(quality.title, systemImage: quality.symbol)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(quality == .poor ? .orange : .green)
                                    }
                                }
                            }
                        }
                        if let low = summary.historicalLow {
                            HStack {
                                Label(.Library.historicalLow, systemImage: "chart.line.downtrend.xyaxis")
                                Spacer()
                                Text(low.price.formatted).font(.callout.weight(.semibold))
                                Text(low.timestamp.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        let offers = summary.offers.isEmpty ? (summary.bestOffer.map { [$0] } ?? []) : summary.offers
                        if !offers.isEmpty {
                            Divider()
                            ForEach(offers.sorted { $0.price.amount < $1.price.amount }) { offer in
                                discoveryOfferRow(offer)
                            }
                        } else {
                            Text(.Library.noCurrentOffers).font(.callout).foregroundStyle(.secondary)
                        }
                    } else if store.isDiscoveryPriceLoading(for: discoveryGame) {
                        ProgressView(.Library.loadingOffers)
                    } else {
                        Text(ITADPriceService.isConfigured ? .Library.priceDataUnavailable : .Library.priceAPIKeyForOffers)
                            .foregroundStyle(.secondary)
                    }
                    Text(.Library.offerLinksByItad)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                discoveryPriceHistorySection(for: discoveryGame)
            }
        }
    }

    private func discoveryOfferRow(_ offer: ITADOffer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(offer.shop.name).font(.callout.weight(.semibold))
                let platformNames = offer.platforms.map(\.name).joined(separator: " · ")
                let drmNames = offer.drm.map(\.name).joined(separator: " · ")
                if !platformNames.isEmpty || !drmNames.isEmpty {
                    Text([platformNames, drmNames].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 7) {
                    Text(offer.price.formatted).font(.callout.weight(.semibold))
                    if let discount = offer.discountLabel {
                        Text(discount).font(.caption2.weight(.bold)).foregroundStyle(.green)
                    }
                }
                if let url = URL(string: offer.url) {
                    Link(.Library.viewOffer, destination: url)
                        .font(.caption).foregroundStyle(.cyan)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func discoveryPriceHistorySection(for game: AppleGamingWikiGame) -> some View {
        detailCard(.Library.priceHistoryTitle, symbol: "chart.xyaxis.line") {
            Picker(.Library.period, selection: $priceHistoryRange) {
                ForEach(DiscoveryPriceHistoryRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            if priceHistoryLoading {
                ProgressView(.Library.loadingPriceHistory)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if priceHistory.isEmpty {
                Text(.Library.noPriceHistory)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                Chart(priceHistory.sorted { $0.timestamp < $1.timestamp }) { point in
                    LineMark(
                        x: .value(.Library.date, point.timestamp),
                        y: .value(.Library.price, point.deal.price.amount)
                    )
                    .foregroundStyle(by: .value(.Library.store, point.shop.name))
                    PointMark(
                        x: .value(.Library.date, point.timestamp),
                        y: .value(.Library.price, point.deal.price.amount)
                    )
                    .foregroundStyle(by: .value(.Library.store, point.shop.name))
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 220)
            }
            Text(.Library.historyByItad)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var dependenciesSection: some View {
        let environmentID = linkedEnvironment!.id
        let statuses = store.dependencyStatuses(for: environmentID, application: linkedApplication)
        let required = statuses.filter { $0.recommendation == .required }
        let recommended = statuses.filter { $0.recommendation == .recommended }
        let optional = statuses.filter { $0.recommendation == .optional }
        let canInstallRequired = required.contains { $0.state == .missing || $0.state == .failed }
        return detailCard(.Library.dependenciesTitle, symbol: "shippingbox.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text(.Library.dependenciesDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !required.isEmpty {
                    dependencyGroup(.Library.required, statuses: required, environmentID: environmentID)
                }
                if !recommended.isEmpty {
                    dependencyGroup(.Library.recommendedForGame, statuses: recommended, environmentID: environmentID)
                }
                dependencyGroup(.Library.optional, statuses: optional, environmentID: environmentID)
                if canInstallRequired {
                    Button(.Library.installRequiredDependencies, systemImage: "arrow.down.circle.fill") {
                        store.installRequiredDependencies(for: environmentID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(statuses.contains { $0.state == .installing })
                }
            }
        }
    }

    @ViewBuilder
    private func dependencyGroup(_ title: LocalizedStringResource, statuses: [RuntimeDependencyStatus], environmentID: UUID) -> some View {
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
                    Text(.Library.installed).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                } else {
                    Button(status.state == .failed ? .Library.retry : .Library.install) {
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
            detailCard(.Library.gameSetupTitle, symbol: "gearshape.fill") {
                metric(.Library.runtime, value: environment.runtime, symbol: "internaldrive")
                metric(.Library.graphics, value: environment.graphics, symbol: "display")
                metric(.Library.windowsVersion, value: environment.windowsVersion, symbol: "window.ceiling")
                let required = store.dependencyStatuses(for: environment.id, application: application).filter { $0.recommendation == .required }
                let componentStatus: LocalizedStringResource = if required.isEmpty {
                    .Library.noneRequired
                } else if required.allSatisfy({ $0.state == .installed }) {
                    .Library.ready
                } else {
                    .Library.requiresAttention
                }
                metric(.Library.components, value: componentStatus, symbol: "checkmark.circle")
                HStack(spacing: 10) {
                    Button(.Library.configure) { compatibilityApplication = application }
                        .buttonStyle(BorealSecondaryActionButtonStyle())
                    Button(.Library.components, systemImage: "arrow.right") { selectedTab = .compatibility }
                        .buttonStyle(BorealSecondaryActionButtonStyle())
                }
            }
        }
    }

    private var compatibilityRating: CompatibilityRating {
        if let discoveryGame {
            switch discoveryGame.bestRating {
            case .perfect: return .excellent
            case .playable: return .good
            case .runs, .menu: return .limited
            case .unplayable: return .unsupported
            case .unknown, .notApplicable: break
            }
        }
        return currentGame.compatibility?.tier.rating ?? linkedApplication?.compatibility ?? .unknown
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
        detailCard(.Library.compatibilityTitle, symbol: "gamecontroller.fill") {
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
                            HStack(spacing: 4) {
                                Text(compatibilityRating.localizedTitle)
                                Text(.Library.compatibilityLabel)
                            }
                                .font(.system(size: 18, weight: .semibold))
                            Text(discoveryGame != nil ? .Library.basedOnAppleGamingWiki : (currentGame.compatibility == nil ? .Library.noCommunityReports : .Library.basedOnCommunityReports))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if width < 1000 { compatibilityDetailsButton.frame(maxWidth: width >= 520 ? 140 : .infinity) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: width < 360 ? 1 : 2), alignment: .leading, spacing: 12) {
                    if let graphics = linkedEnvironment?.graphics {
                        compatibilityFact(.Library.graphics, value: graphics, symbol: "display")
                    } else {
                        compatibilityFact(.Library.graphics, value: .Library.notConfigured, symbol: "display")
                    }
                    if let discoveryGame {
                        compatibilityFact(.Library.community, value: "\(discoveryGame.availableRatings.count) \(String(localized: .Compatibility.methods)) · \(String(localized: discoveryGame.bestRating.localizedDisplayName))", symbol: "person.2.fill")
                    } else if let compatibility = currentGame.compatibility {
                        compatibilityFact(.Library.community, value: "\(compatibility.reportCount.formatted()) \(String(localized: .Compatibility.reports)) · \(String(localized: compatibility.tier.localizedTitle))", symbol: "person.2.fill")
                    } else {
                        compatibilityFact(.Library.community, value: .Library.noReports, symbol: "person.2.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                if width >= 1000 { compatibilityDetailsButton.frame(width: 150) }
            }
        }
    }

    private var compatibilityDetailsButton: some View {
        Button(.Library.viewDetails, systemImage: "arrow.right") { selectedTab = .compatibility }
            .buttonStyle(BorealSecondaryActionButtonStyle())
    }

    private func compatibilityFact(_ title: LocalizedStringResource, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.indigo.opacity(0.9))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func compatibilityFact(_ title: LocalizedStringResource, value: LocalizedStringResource, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.indigo.opacity(0.9))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aboutGameSection: some View {
        detailCard(.Library.aboutThisGameTitle, symbol: "doc.text.fill") {
            if let summary = currentGame.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(2)
                    .lineLimit(showsFullDescription ? nil : 4)
                    .textSelection(.enabled)
                if summary.count > 160 {
                    Button(showsFullDescription ? .Library.showLess : .Library.readMore) { showsFullDescription.toggle() }
                        .buttonStyle(.plain).foregroundStyle(.cyan).font(.caption.weight(.semibold))
                }
            } else {
                Text(.Library.noStoreDescription).font(.callout).foregroundStyle(.secondary)
            }
            if let developer = currentGame.developer {
                Divider()
                metric(.Library.developer, value: developer, symbol: "person.2")
            }
            metric(.Library.source, value: currentGame.provider.rawValue, symbol: "bag")
            if let discoveryGame {
                switch store.gogRevivedAvailability(for: discoveryGame) {
                case .available(let entry):
                    if let url = URL(string: entry.pageURL) {
                        Divider()
                        Link(destination: url) {
                            Label(.Library.openOnGogRevived, systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BorealSecondaryActionButtonStyle())
                        .help("GOG Revived lists this title as \(entry.title).")
                    }
                case .unknown, .checking:
                    Divider()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(.Library.checkingGogRevived).font(.caption).foregroundStyle(.secondary)
                    }
                case .notFound:
                    Divider()
                        Label(.Library.notListedOnGogRevived, systemImage: "minus.circle")
                        .font(.caption).foregroundStyle(.secondary)
                case .unavailable:
                    Divider()
                        Label(.Library.gogStatusUnavailable, systemImage: "questionmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
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

    private var storeImageFailurePlaceholder: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            Label(.Library.imageUnavailable, systemImage: "photo.badge.exclamationmark")
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
            if let discoveryGame, !isInLibrary {
                Button(.Library.addToLibrary, systemImage: "plus") {
                    store.addDiscoveryGameToLibrary(discoveryGame, details: currentGame)
                }
                .buttonStyle(BorealPrimaryActionButtonStyle())
            } else if let operation = storeOperation {
                storeOperationPrimaryButton(operation)
            } else if store.installation(for: currentGame)?.state == .volumeUnavailable {
                primaryStatusButton("Volume unavailable", symbol: "externaldrive.badge.xmark")
            } else if game.provider == .steam {
                if store.isInstalled(currentGame), store.installedPlatform(for: currentGame) == .nativeMacOS, store.installedLocation(for: currentGame) != nil {
                    Button(.Library.play, systemImage: "play.fill") { openNativeInstallation() }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                } else if let app = linkedApplication {
                    runtimeLaunchControl(for: app, playTitle: .Library.play)
                } else if currentGame.supportsNativeMacOS == true {
                    Button(store.isInstalled(currentGame) ? .Library.play : .Library.install, systemImage: store.isInstalled(currentGame) ? "play.fill" : "arrow.down.circle.fill") { openSteam() }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                } else if currentGame.supportsWindows == true, storeOperation == nil {
                    Button(.Library.installWindowsVersion, systemImage: "arrow.down.circle.fill") { showsInstallationOptions = true }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                } else {
                    Button(.Library.openInSteam, systemImage: "arrow.up.right.square") { openSteam() }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
                }
            } else if currentGame.resolvedEntitlementState == .accountDisconnected, linkedApplication == nil {
                primaryStatusButton("Reconnect account…", symbol: "person.crop.circle.badge.exclamationmark")
            } else if store.isInstalled(currentGame) {
                if let app = linkedApplication {
                    runtimeLaunchControl(for: app, playTitle: .Library.play)
                } else if store.usesManagedRuntime(for: currentGame), storeOperation == nil {
                    primaryStatusButton("Preparing compatibility…", symbol: "gearshape.2.fill")
                } else if store.installedPlatform(for: currentGame) == .nativeMacOS {
                    Button(.Library.play, systemImage: "play.fill") { openNativeInstallation() }
                        .buttonStyle(BorealPrimaryActionButtonStyle())
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

    private var isInLibrary: Bool {
        store.storeGames.contains {
            $0.provider == currentGame.provider && $0.externalID == currentGame.externalID
        }
    }

    private var moreActionsMenu: some View {
        Menu {
            if let app = linkedApplication {
                if app.usesStoreMetadataOnly {
                    Button(.Library.renameGame, systemImage: "pencil") {
                        renameValue = app.name
                        showsRenameDialog = true
                    }
                }
                Button(.Library.compatibilitySettings, systemImage: "slider.horizontal.3") {
                    compatibilityApplication = app
                }
                if !app.isInstallerOnly, !app.isSteamRuntimeHost {
                    Button(.Library.installPatchOrDLC, systemImage: "shippingbox.and.arrow.backward") {
                        selectWindowsInstaller(for: app)
                    }
                    .disabled(app.status == .running || app.status.isBusy || storeOperation != nil)
                }
                if GameLaunchCompatibility.supportsDLSSUnlocker(for: app) {
                    if store.dlssUnlockerInstalled(for: app) {
                        Button("Remove GTA SA DLSS Unlocker", systemImage: "arrow.uturn.backward", role: .destructive) {
                            showsDLSSUnlockerUninstallConfirmation = true
                        }
                        .disabled(app.status == .running || app.status.isBusy || storeOperation != nil)
                    } else {
                        Button("Install GTA SA DLSS Unlocker…", systemImage: "arrow.down.app") {
                            selectDLSSUnlockerArchive(for: app)
                        }
                        .disabled(app.status == .running || app.status.isBusy || storeOperation != nil)
                    }
                }
                let gameActions = store.auxiliaryExecutables(for: app)
                if !gameActions.isEmpty {
                    Section(content: {
                        ForEach(gameActions) { action in
                            Button(action.displayName, systemImage: action.role.symbol) {
                                store.runAuxiliaryExecutable(action, for: app.id)
                            }
                            .disabled(app.status == .running || app.status.isBusy || storeOperation != nil)
                        }
                    }, header: { Text(.Library.gameActions) })
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
            if store.installedLocation(for: currentGame) != nil {
                Button(.Library.showGameFiles, systemImage: "folder") { showGameFiles() }
            }
            Divider()
            let hasCustomArtwork = currentGame.customArtworkPath != nil || currentGame.customArtworkOriginalPath != nil
            Button(hasCustomArtwork ? "Edit Cover…" : "Change Cover…", systemImage: "photo.on.rectangle") {
                chooseCustomCover()
            }
            if hasCustomArtwork {
                Button("Reset to Default", systemImage: "arrow.uturn.backward") {
                    store.resetCustomArtwork(forStoreGameID: currentGame.id)
                }
            }
            if !store.isInstalled(currentGame) && linkedApplication == nil {
                Button(.Library.locateInstalledGame, systemImage: "folder.badge.plus") { locateInstalledGame() }
            }

            if currentGame.provider == .steam {
                Button(.Library.viewSteamStorePage, systemImage: "arrow.up.right.square") { openStorePage() }
            }
            if store.isInstalled(currentGame), store.supportsStoreGameUpdate(currentGame) {
                Button(.Library.checkForUpdates, systemImage: "arrow.triangle.2.circlepath") {
                    store.updateStoreGame(currentGame)
                }
                .disabled(storeOperation != nil || !currentGame.resolvedEntitlementState.isUsable)
            }
            if store.isInstalled(currentGame), store.supportsStoreGameVerification(currentGame) {
                Button(.Library.verifyGameFiles, systemImage: "checkmark.shield") {
                    store.verifyStoreGame(currentGame)
                }
                .disabled(storeOperation != nil || !currentGame.resolvedEntitlementState.isUsable)
            }
            if store.isInstalled(currentGame) || linkedApplication != nil {
                Divider()
                Button(.Library.uninstall, systemImage: "trash", role: .destructive) { showsUninstallConfirmation = true }
            }
        } label: {
            squareMenuLabel(symbol: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(Text(.Library.moreActions))
        .accessibilityLabel(Text(.Library.moreActions))
    }

    @ViewBuilder private func runtimeLaunchControl(for app: WindowsApplication, playTitle: LocalizedStringResource) -> some View {
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
        if store.isInstalled(currentGame) {
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
        store.runtimeEngine(for: app)
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
            Label(.Library.prepareToPlay, systemImage: "wand.and.stars")
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
        } else if store.isInstalled(currentGame) {
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
        guard totalSeconds > 0 else { return String(localized: .Library.notPlayed) }
        return formatDuration(totalSeconds)
    }

    private func libraryOverview(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: width >= 760 ? 4 : (width >= 360 ? 2 : 1)), spacing: 12) {
                overviewMetric(.Library.playtime, value: playtime, symbol: "clock")
                overviewMetric(.Library.lastPlayed, value: lastPlayedValue, symbol: "calendar")
                overviewMetric(requiredStorageTitle, value: formattedRequiredStorage, symbol: "internaldrive")
                overviewMetric(.Library.compatibilityTitle, value: String(localized: currentGame.supportsNativeMacOS == true ? .Compatibility.nativeTitle : compatibilityRating.localizedTitle), symbol: compatibilityRating.symbol, tint: currentGame.supportsNativeMacOS == true ? .mint : compatibilityTint)
            }
        }
    }

    private var lastPlayedValue: String {
        if store.activePlaySessionStart(for: currentGame) != nil { return String(localized: .Library.playingNow) }
        return currentGame.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? String(localized: .Library.never)
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
                activityMetric(.Library.totalPlaytime, value: formatDuration(sessions.reduce(0) { $0 + $1.duration }), symbol: "clock")
                activityMetric(.Library.sessions, value: "\(sessions.count)", symbol: "gamecontroller")
                activityMetric(.Library.averageSession, value: formatDuration(statistics.averageSession), symbol: "chart.bar.fill")
                activityMetric(.Library.longestSession, value: formatDuration(statistics.longestSession), symbol: "trophy")
                activityMetric(.Library.lastPlayed, value: lastPlayedValue, symbol: "calendar", subtitle: currentGame.lastPlayed.map { $0.formatted(.relative(presentation: .named)) })
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

    private func activityMetric(_ title: LocalizedStringResource, value: String, symbol: String, subtitle: String? = nil) -> some View {
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
        activityCard(.Library.trackedByBoreal, symbol: "info.circle.fill", minimumHeight: 100) {
            HStack(spacing: 16) {
                Text(.Library.activityTrackingDescription)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(.Library.learnMore) { showsActivityInfo = true }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.06)) }
                    .fixedSize()
                    .popover(isPresented: $showsActivityInfo) {
                        Text(.Library.activityTrackingDetails)
                            .font(.callout).padding(20).frame(width: 320)
                    }
            }
        }
    }

    private func activityWeekCard(_ statistics: GameActivityStatistics, at date: Date) -> some View {
        activityCard(.Library.thisWeek, symbol: "calendar.badge.clock", minimumHeight: 100) {
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
                    HStack(spacing: 4) {
                        Text(.Library.lastWeek)
                        Text(formatDuration(statistics.lastWeek))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func activityChart(_ statistics: GameActivityStatistics) -> some View {
        let days = Array(statistics.days.suffix(activityDayCount))
        return activityCard(.Library.playtimeOverTime, symbol: "chart.xyaxis.line", minimumHeight: 180, showsPeriod: true) {
            Chart(days) { day in
                AreaMark(x: .value(.Library.date, day.date), y: .value(.Library.minutes, day.duration / 60))
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.3), .blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value(.Library.date, day.date), y: .value(.Library.minutes, day.duration / 60))
                    .foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 2))
                if activityDayCount == 7 {
                    PointMark(x: .value(.Library.date, day.date), y: .value(.Library.minutes, day.duration / 60))
                        .foregroundStyle(.blue).symbolSize(28)
                }
                if let selection = selectedActivityDate,
                   Calendar.autoupdatingCurrent.isDate(day.date, inSameDayAs: selection) {
                    RuleMark(x: .value(.Library.selectedDate, day.date))
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
                    AxisValueLabel { if let minutes = value.as(Double.self) { Text("\(minutes.formatted(.number.precision(.fractionLength(0)))) \(String(localized: .Library.minutesShort))") } }
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
        return activityCard(.Library.activityHeatmap, symbol: "square.grid.3x3.fill", minimumHeight: 180) {
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
                            activityLevelLabel(level)
                        }
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
            }
            .frame(height: 126)
        }
    }

    @ViewBuilder
    private func activityLevelLabel(_ level: Int) -> some View {
        switch level {
        case 0: Text(.Library.noActivity)
        case 1: Text(.Library.littleActivity)
        case 2: Text(.Library.someActivity)
        case 4: Text(.Library.moreActivity)
        default: EmptyView()
        }
    }

    private func activityHistory(_ sessions: [GamePlaySession]) -> some View {
        activityCard(.Library.sessionHistory, symbol: "list.bullet.rectangle", sessionCount: sessions.count) {
            if sessions.isEmpty {
                Text(.Library.noSessionsDescription)
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 18)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                        GridRow {
                            Text(.Library.date).frame(maxWidth: .infinity, alignment: .leading)
                            Text(.Library.startTime).frame(maxWidth: .infinity, alignment: .leading)
                            Text(.Library.endTime).frame(maxWidth: .infinity, alignment: .leading)
                            Text(.Library.duration).frame(maxWidth: .infinity, alignment: .leading)
                            Text(.Library.status).frame(maxWidth: .infinity, alignment: .leading)
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
                                Text(session.isActive ? .Library.playingNow : .Library.completed)
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
        _ title: LocalizedStringResource, symbol: String, minimumHeight: CGFloat = 0,
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
                    HStack(spacing: 4) {
                        Text("\(sessionCount)")
                        Text(.Library.sessions)
                    }
                    .font(.caption).foregroundStyle(.secondary)
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
        let hoursUnit = String(localized: .Library.hoursShort)
        let minutesUnit = String(localized: .Library.minutesShort)
        if hours > 0 { return String(format: "%d %@ %02d %@", hours, hoursUnit, minutes, minutesUnit) }
        if minutes > 0 { return "\(minutes) \(minutesUnit)" }
        return "\(seconds) \(String(localized: .Library.secondsShort))"
    }

    private func overviewMetric(_ title: LocalizedStringResource, value: String, symbol: String, tint: Color = .blue) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)) }
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
        guard let bytes = currentGame.sizeEstimate?.downloadBytes, bytes > 0 else { return String(localized: .Library.notProvided) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var requiredStorageTitle: LocalizedStringResource {
        store.installedSize(for: currentGame).map { $0 > 0 } == true ? .Library.onDisk : .Library.requiredSpace
    }

    private var formattedRequiredStorage: String {
        if let bytes = store.installedSize(for: currentGame), bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        guard let estimate = currentGame.sizeEstimate,
              let bytes = estimate.installedBytes, bytes > 0 else { return String(localized: .Library.notProvided) }
        let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return estimate.source.isExactManifest ? formatted : "≈ \(formatted)"
    }

    private var sizeSource: String {
        if store.installedSize(for: currentGame).map({ $0 > 0 }) == true { return "Installed files" }
        switch currentGame.sizeEstimate?.source {
        case .gogManifest: return "GOG manifest"
        case .epicManifest: return "Epic manifest"
        case .steamStoreRequirement: return "Steam store requirement"
        case nil: return "Unavailable"
        }
    }

    private var installationLocation: String {
        guard let path = store.installedLocation(for: currentGame)?.path else { return "Not installed" }
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
            detailCard(.Library.mediaTitle, symbol: "photo", actionTitle: .Library.viewAllMedia, action: {
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
            let installationState = store.installation(for: currentGame)?.state
            let installationIsReady = installationState == .installed
            if store.installedLocation(for: currentGame) != nil || store.installedSize(for: currentGame) != nil || currentGame.sizeEstimate != nil {
                detailCard(.Library.installationTitle, symbol: "internaldrive.fill") {
                    Label {
                        Text(installationState == .volumeUnavailable
                            ? "Volume unavailable"
                            : (installationIsReady ? String(localized: .Library.installed) : String(localized: .Library.notInstalled)))
                    } icon: {
                        Image(systemName: installationState == .volumeUnavailable
                            ? "externaldrive.badge.xmark"
                            : (installationIsReady ? "checkmark.circle.fill" : "arrow.down.circle"))
                    }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(installationState == .volumeUnavailable ? Color.orange : (installationIsReady ? Color.mint : Color.secondary))
                    Divider()
                    metric(requiredStorageTitle, value: formattedRequiredStorage, symbol: "internaldrive")
                    if let environment = linkedEnvironment {
                        metric(.Library.prefix, value: store.formattedBytes(environment.storageBytes), symbol: "shippingbox")
                    }
                    if store.installedLocation(for: currentGame) != nil {
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(.Library.location).font(.caption).foregroundStyle(.secondary)
                            Text(installationLocation).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                                .help(store.installedLocation(for: currentGame)?.path ?? installationLocation)
                        }
                    }
                    if currentGame.sizeEstimate?.downloadBytes != nil {
                        metric(.Library.download, value: formattedDownloadSize, symbol: "arrow.down.circle")
                    }
                    if store.installedLocation(for: currentGame) != nil {
                        Button(.Library.manageFiles, systemImage: "arrow.right") { selectedTab = .files }
                            .buttonStyle(BorealSecondaryActionButtonStyle())
                    }
                }
            }
            if let environment = linkedEnvironment {
                detailCard(.Library.environmentTitle, symbol: "shippingbox") {
                    metric(.Library.runtime, value: environment.runtime, symbol: "gearshape.2")
                    metric(.Library.graphics, value: environment.graphics, symbol: "display")
                    metric(.Library.windowsVersion, value: environment.windowsVersion, symbol: "window.ceiling")
                    metric(.Library.architecture, value: environment.architecture, symbol: "cpu")
                    if let application = linkedApplication {
                        Button(.Library.configure, systemImage: "arrow.right") { compatibilityApplication = application }
                            .buttonStyle(BorealSecondaryActionButtonStyle())
                    }
                }
            }
            detailCard(.Library.actionsTitle, symbol: "ellipsis") {
                if store.installedLocation(for: currentGame) != nil {
                    Button(.Library.openGameFolder, systemImage: "folder") { showGameFiles() }
                        .buttonStyle(BorealRailActionButtonStyle())
                }
                if !store.isInstalled(currentGame) && linkedApplication == nil {
                    Button(.Library.locateInstalledGame, systemImage: "folder.badge.plus") { locateInstalledGame() }
                        .buttonStyle(BorealRailActionButtonStyle())
                }
                if currentGame.provider == .steam {
                    Button(.Library.viewSteamStorePage, systemImage: "arrow.up.right.square") { openStorePage() }
                        .buttonStyle(BorealRailActionButtonStyle())
                }
                if store.isInstalled(currentGame), store.supportsStoreGameUpdate(currentGame) {
                    Button(.Library.checkForUpdates, systemImage: "arrow.triangle.2.circlepath") {
                        store.updateStoreGame(currentGame)
                    }
                    .buttonStyle(BorealRailActionButtonStyle())
                    .disabled(storeOperation != nil || !currentGame.resolvedEntitlementState.isUsable)
                }
                if store.isInstalled(currentGame), store.supportsStoreGameVerification(currentGame) {
                    Button(.Library.verifyGameFiles, systemImage: "checkmark.shield") {
                        store.verifyStoreGame(currentGame)
                    }
                    .buttonStyle(BorealRailActionButtonStyle())
                    .disabled(storeOperation != nil || !currentGame.resolvedEntitlementState.isUsable)
                }
                if store.isInstalled(currentGame) || linkedApplication != nil {
                    Divider()
                    Button(.Library.uninstall, systemImage: "trash", role: .destructive) {
                        showsUninstallConfirmation = true
                    }
                    .buttonStyle(BorealRailActionButtonStyle())
                }
            }
        }
    }

    private var installationFilesSection: some View {
        detailCard(.Library.installationTitle, symbol: "folder.fill") {
            if let path = store.installedLocation(for: currentGame)?.path {
                metric(.Library.location, value: path, symbol: "folder")
                Button(.Library.openInstallationFolder, systemImage: "folder") { showGameFiles() }
                    .buttonStyle(BorealSecondaryActionButtonStyle())
            }
            if let application = linkedApplication {
                metric(.Library.executable, value: URL(fileURLWithPath: application.executablePath).lastPathComponent, symbol: "doc")
            }
            diskStorageCard
        }
    }

    private var diskStorageCard: some View {
        let report = store.gameDiskReport(for: currentGame)
        return detailCard(.Library.diskUsageTitle, symbol: "internaldrive.fill") {
            ForEach(GameDiskStorageCategory.allCases, id: \.self) { category in
                let item = report?.item(category)
                metric(diskStorageTitle(category), value: item?.bytes.map(store.formattedBytes) ?? String(localized: .Library.unavailable), symbol: category == .shaders ? "sparkles" : "internaldrive")
            }
            Divider()
            Text(.Library.shaderCache).font(.subheadline.weight(.semibold))
            HStack {
                Text(.Library.cacheWarning)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(.Library.clear) { diskStorageCategory = .shaders; showsDiskStorageConfirmation = true }
                    .disabled(report?.item(.shaders)?.bytes == nil)
                Button(.Library.rebuild) { store.rebuildShaderCache(for: currentGame) }
                    .disabled(report?.item(.shaders)?.bytes == nil)
            }
            .buttonStyle(.bordered)
            HStack {
                clearButton(.downloads, title: .Library.removeDownloads, report: report)
                clearButton(.snapshots, title: .Library.deleteOldSnapshots, report: report)
            }
        }
    }

    private func clearButton(_ category: GameDiskStorageCategory, title: LocalizedStringResource, report: GameDiskStorageReport?) -> some View {
        Button(title) { diskStorageCategory = category; showsDiskStorageConfirmation = true }
            .disabled(report?.item(category)?.bytes == nil)
    }

    private func diskStorageTitle(_ category: GameDiskStorageCategory) -> LocalizedStringResource {
        switch category {
        case .gameFiles: .Library.gameFiles
        case .prefix: .Library.prefix
        case .shaders: .Library.shaders
        case .downloads: .Library.download
        case .snapshots: .Library.snapshots
        }
    }

    private var libraryStatus: String {
        if linkedApplication != nil { return "Managed by Boreal" }
        if store.isInstalled(currentGame) { return "Installed" }
        return "In your library"
    }

    private var libraryStatusSymbol: String {
        if linkedApplication?.status == .running { return "play.circle.fill" }
        if linkedApplication != nil { return "checkmark.seal.fill" }
        if store.isInstalled(currentGame) { return "checkmark.circle.fill" }
        return "books.vertical.fill"
    }

    private var actionContext: String {
        if linkedApplication?.status == .running { return "The game is running now." }
        if storeOperation != nil { return "An installation task is currently in progress." }
        if linkedApplication != nil { return "Ready to launch with its configured Boreal runtime." }
        if store.isInstalled(currentGame), store.usesManagedRuntime(for: currentGame) {
            return "Installed locally and ready to prepare its Boreal environment."
        }
        if store.isInstalled(currentGame) { return "Installed locally and ready to open." }
        return "Owned on \(currentGame.provider.rawValue). Install it when you are ready to play."
    }

    private var cardFill: LinearGradient {
        LinearGradient(colors: [Color(red: 0.09, green: 0.125, blue: 0.18), Color(red: 0.065, green: 0.095, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func detailCard<Content: View>(_ title: LocalizedStringResource, symbol: String, actionTitle: LocalizedStringResource? = nil, action: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) -> some View {
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

    private var linkedApplication: WindowsApplication? {
        customApplicationID.flatMap { store.application(id: $0) } ?? store.linkedApplication(for: game)
    }

    private var diskReportTaskID: String {
        "disk-\(game.id.uuidString)-\(store.installedLocation(for: currentGame)?.path ?? "uninstalled")"
    }

    private var linkedEnvironment: WindowsEnvironment? {
        guard let application = linkedApplication else { return nil }
        return store.environment(id: application.environmentID)
    }

    private var preferredPlatformName: String {
        store.preferredStoreInstallationPlatform(for: currentGame) == .nativeMacOS ? "macOS" : "Windows"
    }

    private var installButtonTitle: LocalizedStringResource {
        store.preferredStoreInstallationPlatform(for: currentGame) == .nativeMacOS
            ? .Library.installNativeMacVersion
            : .Library.installWindowsVersion
    }

    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(.Library.macCompatibility, systemImage: "checkmark.shield.fill")
                .font(.headline)
            if let discoveryGame, !discoveryGame.availableRatings.isEmpty {
                ForEach(discoveryGame.availableRatings, id: \.title) { entry in
                    HStack {
                        Text(entry.localizedTitle)
                        Spacer()
                        Label { Text(entry.rating.localizedDisplayName) } icon: { Image(systemName: entry.rating.symbol) }
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(entry.rating.color)
                    }
                    Divider().opacity(0.45)
                }
                Text(.Library.appleGamingWikiDisclaimer)
                    .font(.caption).foregroundStyle(.secondary)
            } else if let profile = currentGame.compatibility {
                HStack(alignment: .top, spacing: 18) {
                    MacCompatibilityBadge(rating: profile.tier.rating)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(.Library.wineCompatibility)
                            .fontWeight(.medium)
                        Text(compatibilitySummary(profile))
                            .font(.callout).foregroundStyle(.secondary)
                        Text(.Library.wineCompatibilityDisclaimer)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    .Library.noCompatibilityReports,
                    systemImage: "questionmark.circle",
                    description: Text(.Library.noCompatibilityResult)
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
        var parts = [String(localized: profile.tier.localizedTitle)]
        if let score = profile.score { parts.append("\(Int(score))/5 \(String(localized: .Compatibility.stars))") }
        if profile.reportCount > 0 { parts.append("\(profile.reportCount.formatted()) \(String(localized: .Compatibility.reports))") }
        if let confidence = profile.confidence, profile.score == nil {
            parts.append("\(localizedConfidence(confidence)) \(String(localized: .Compatibility.confidence))")
        }
        if let trending = profile.trendingTier, trending != profile.tier { parts.append("\(String(localized: .Compatibility.trending)): \(String(localized: trending.localizedTitle))") }
        if let date = profile.sourceUpdatedAt, profile.score != nil {
            parts.append("\(String(localized: .Compatibility.updated)) \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private func localizedConfidence(_ confidence: String) -> String {
        switch confidence.lowercased() {
        case "high": String(localized: .Compatibility.highConfidence)
        case "medium", "moderate": String(localized: .Compatibility.mediumConfidence)
        case "low": String(localized: .Compatibility.lowConfidence)
        default: confidence.capitalized
        }
    }

    private func metric(_ title: LocalizedStringResource, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(value).font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: LocalizedStringResource, value: LocalizedStringResource, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(value).font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        guard let installPath = store.installedLocation(for: currentGame)?.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installPath)])
    }

    private func chooseCustomCover() {
        let source: (data: Data, crop: ArtworkCrop)? = {
            if let originalPath = currentGame.customArtworkOriginalPath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: originalPath)),
               NSImage(data: data) != nil {
                return (data, currentGame.customArtworkCrop ?? .centered)
            }
            if let processedPath = currentGame.customArtworkPath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: processedPath)),
               NSImage(data: data) != nil {
                return (data, .centered)
            }
            return nil
        }()
        if let source {
            coverEditorState = StoreGameCoverEditorState(
                gameID: currentGame.id,
                sourceData: source.data,
                crop: source.crop
            )
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Change Cover"
        panel.message = "Select an image to crop for this game's cover."
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return }
        coverEditorState = StoreGameCoverEditorState(gameID: currentGame.id, sourceData: data, crop: .centered)
    }

    private func openSteam() {
        let action = store.isInstalled(currentGame) ? "rungameid" : (currentGame.supportsNativeMacOS == true ? "install" : "store")
        if action == "rungameid", store.installedPlatform(for: currentGame) == .nativeMacOS, let path = store.installedLocation(for: currentGame)?.path {
            GameOverlayController.shared.expectNativeGame(
                name: currentGame.name,
                installationURL: URL(fileURLWithPath: path, isDirectory: true)
            )
        }
        if let url = URL(string: "steam://\(action)/\(game.externalID)") { NSWorkspace.shared.open(url) }
    }

    private func openNativeInstallation() {
        guard let path = store.installedLocation(for: currentGame)?.path else { return }
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
        panel.message = store.preferredStoreInstallationPlatform(for: currentGame) == .nativeMacOS
            ? "Choose the installed macOS .app or the main Windows .exe file."
            : "Choose the installed game’s main Windows .exe file."
        panel.prompt = "Add to Boreal"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types = [UTType(filenameExtension: "exe") ?? .data]
        if store.preferredStoreInstallationPlatform(for: currentGame) == .nativeMacOS { types.append(.applicationBundle) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.registerExistingGame(game, at: url)
    }

    private func selectWindowsInstaller(for application: WindowsApplication) {
        let panel = NSOpenPanel()
        panel.title = "Install Patch or DLC for \(application.name)"
        panel.message = "Choose a Windows installer to run inside \(application.name)’s existing environment."
        panel.prompt = "Run Installer"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "exe") ?? .data,
            UTType(filenameExtension: "msi") ?? .data,
        ]
        guard panel.runModal() == .OK, let installer = panel.url else { return }
        store.runWindowsInstaller(installer, for: application.id)
    }

    private func selectDLSSUnlockerArchive(for application: WindowsApplication) {
        let panel = NSOpenPanel()
        panel.title = "Install GTA SA DLSS Unlocker"
        panel.message = "Choose the ZIP downloaded from the linked mod page. Boreal will validate and install only the unlocker files."
        panel.prompt = "Install Unlocker"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let archive = panel.url else { return }
        store.installDLSSUnlocker(archive, for: application.id)
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

private struct StoreGameCoverEditorState: Identifiable {
    let gameID: UUID
    let sourceData: Data
    let crop: ArtworkCrop

    var id: UUID { gameID }
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
    private enum InstallationChoice: Hashable {
        case install
        case existing
    }

    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let game: StoreLibraryGame
    let completion: (URL?) -> Void
    @State private var destination: URL
    @State private var choice: InstallationChoice = .install
    @State private var hasStartedInstallation = false
    @State private var showsProgressDetails = false

    init(game: StoreLibraryGame, defaultDestination: URL, completion: @escaping (URL?) -> Void) {
        self.game = game
        self.completion = completion
        _destination = State(initialValue: defaultDestination)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if hasStartedInstallation, let operation = store.storeGameOperation(for: game) {
                progressContent(operation)
            } else {
                configurationContent
            }
        }
        .padding(28)
        .frame(width: 650)
        .background(
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.13), Color(red: 0.055, green: 0.06, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(.dark)
        .onChange(of: store.storeGameOperation(for: game)) { previous, current in
            if hasStartedInstallation, previous != nil, current == nil { dismiss() }
        }
    }

    private func infoBadge(_ title: String, symbol: String?) -> some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func optionRow<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout)
                .frame(width: 135, alignment: .leading)
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            content()
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    @ViewBuilder private func progressContent(_ operation: StoreGameOperationState) -> some View {
        if let progress = operation.progress {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Installing \(game.name)…")
                            .font(.title3.bold())
                        Text(progress.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
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
                } else {
                    ProgressView().progressViewStyle(.linear).tint(.blue)
                }
                HStack {
                    Text(progress.phase.detail)
                    Spacer()
                    Text(progressSummary(progress))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                progressSteps(progress)

                HStack {
                    if let rawDetail = progress.rawDetail {
                        DisclosureGroup("Show details", isExpanded: $showsProgressDetails) {
                            Text(rawDetail)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.top, 8)
                        }
                    }
                    Spacer()
                    if operation.isCancellable {
                        Button("Pause Installation") { store.cancelStoreGameOperation(game) }
                    } else if operation.isResumable {
                        Button("Resume") { store.resumeStoreGameOperation(game) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)

                Label("You can close Boreal. The installation will continue in the background.", systemImage: "lightbulb.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.orange.opacity(0.25)) }
            }
        } else if case .awaitingProvider(let message) = operation {
            statusContent(title: "Continue in \(game.provider.rawValue)", message: message, symbol: game.provider.symbol)
        } else if case .failed(let message) = operation {
            statusContent(title: "Installation failed", message: message, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func progressSteps(_ progress: StoreGameOperationProgress) -> some View {
        let phases: [StoreGameOperationPhase] = [.preparing, .downloading, .installing, .verifying]
        let currentIndex = phases.firstIndex(of: progress.phase) ?? 0
        return VStack(spacing: 0) {
            ForEach(Array(phases.enumerated()), id: \.element) { index, phase in
                HStack(spacing: 11) {
                    Image(systemName: index < currentIndex ? "checkmark.circle.fill" : (index == currentIndex ? "circle.dotted.circle.fill" : "circle.fill"))
                        .foregroundStyle(index < currentIndex ? Color.green : (index == currentIndex ? Color.blue : Color.secondary.opacity(0.35)))
                    Text(phaseStepTitle(phase))
                        .foregroundStyle(index <= currentIndex ? .primary : .secondary)
                    Spacer()
                }
                .padding(.vertical, 9)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10)) }
    }

    private func statusContent(title: String, message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func phaseStepTitle(_ phase: StoreGameOperationPhase) -> String {
        switch phase {
        case .preparing: "Prepare environment"
        case .downloading: "Download game files (\(game.provider.rawValue))"
        case .installing: "Install game files"
        case .verifying: "Finalize installation"
        }
    }

    private func progressSummary(_ progress: StoreGameOperationProgress) -> String {
        var values: [String] = []
        if let transferred = progress.transferred, let total = progress.total {
            values.append("\(transferred) / \(total)")
        } else if let total = progress.total {
            values.append(total)
        }
        if let rate = progress.transferRate { values.append(rate) }
        if let remaining = progress.estimatedTimeRemaining { values.append("~ \(remaining) left") }
        return values.joined(separator: "  •  ")
    }

    private func beginInstallation() {
        hasStartedInstallation = true
        completion(game.provider == .steam ? nil : destination)
    }

    private func chooseExistingInstallation() {
        let panel = NSOpenPanel()
        panel.title = "Locate \(game.name)"
        panel.message = existingInstallationExplanation
        panel.prompt = "Add to Boreal"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types = [UTType(filenameExtension: "exe") ?? .data]
        if installationPlatform == .nativeMacOS { types.append(.applicationBundle) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.registerExistingGame(game, at: url)
        dismiss()
    }

    private var gameSummary: String { game.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var installationPlatform: StoreGameInstallationPlatform {
        store.preferredStoreInstallationPlatform(for: game)
    }
    private var platformName: String { installationPlatform == .nativeMacOS ? "macOS" : "Windows" }
    private var targetEnvironmentName: String {
        if installationPlatform == .nativeMacOS { return "Native macOS application" }
        if game.provider == .steam { return "Boreal · Steam for Windows" }
        return "Boreal · automatic Wine/GPTK environment"
    }
    private var primaryActionTitle: String {
        installationPlatform == .nativeMacOS ? "Install Native Version" : (game.provider == .steam ? "Open Steam Installer" : "Install")
    }
    private var installationExplanation: String {
        if installationPlatform == .nativeMacOS {
            return "Boreal will download the native Mac release and add it to your Library."
        }
        if game.provider == .steam {
            return "Boreal will prepare Steam for Windows. Sign in and choose the game library in Steam; Boreal will use that client for installation and launch."
        }
        return "Game files will be downloaded from \(game.provider.rawValue). Boreal will inspect the executable, prepare a compatible isolated Windows environment, and add the game to your Library."
    }
    private var existingInstallationExplanation: String {
        installationPlatform == .nativeMacOS
            ? "Choose the installed macOS .app or the main Windows .exe file."
            : "Choose the installed game’s main Windows .exe file."
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            GameArtworkView(game: game, width: 130, height: 154)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                Text(game.name)
                    .font(.system(size: 27, weight: .bold))
                    .lineLimit(2)
                HStack(spacing: 9) {
                    infoBadge(game.provider.rawValue, symbol: game.provider.symbol)
                    infoBadge(platformName, symbol: nil)
                    infoBadge(formattedRequiredSize, symbol: nil)
                }
                if !gameSummary.isEmpty {
                    Text(gameSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close")
        }
        .padding(.bottom, 28)
    }

    private var configurationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Installation method", selection: $choice) {
                Label("Install and add to Library", systemImage: "arrow.down.to.line").tag(InstallationChoice.install)
                Label("Use existing installation", systemImage: "folder").tag(InstallationChoice.existing)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            if choice == .install {
                installationOptions
                architectureCard
            } else {
                existingInstallationCard
            }

            actionBar
        }
    }

    private var installationOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installation options", systemImage: "gearshape")
                .font(.headline)
            VStack(spacing: 0) {
                optionRow(title: "Target environment", symbol: installationPlatform == .nativeMacOS ? "apple.logo" : "wineglass") {
                    Text(targetEnvironmentName).lineLimit(1)
                }
                Divider().opacity(0.45)
                optionRow(title: "Installation path", symbol: "folder") {
                    if game.provider == .steam {
                        Text("Selected in Steam").foregroundStyle(.secondary)
                    } else {
                        Text(destination.path).lineLimit(1).truncationMode(.middle)
                        Button("Change…") { chooseDestination() }
                    }
                }
                Divider().opacity(0.45)
                HStack(spacing: 10) {
                    storageSummary(title: "Download", value: formattedDownloadSize, symbol: "arrow.down.circle")
                    storageSummary(title: "Required", value: formattedRequiredSize, symbol: "internaldrive")
                    storageSummary(title: "Available", value: formattedCapacity, symbol: "externaldrive")
                }
                .padding(12)
            }
            .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10)) }
        }
    }

    private var existingInstallationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Use an existing installation", systemImage: "folder.badge.plus")
                .font(.headline)
            Text(existingInstallationExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.blue.opacity(0.35)) }
    }

    private var architectureCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("What will happen?", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            Text(installationExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            architectureSummary
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.blue.opacity(0.35)) }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .controlSize(.large)
            Button(choice == .install ? primaryActionTitle : "Choose Installed Game…", systemImage: choice == .install ? "arrow.down.to.line" : "folder") {
                if choice == .install { beginInstallation() }
                else { chooseExistingInstallation() }
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(choice == .install && game.provider != .steam && !destinationIsUsable)
        }
        .padding(.top, 4)
    }

    private var destinationIsUsable: Bool {
        BorealStore.gameInstallationDestinationIsAvailable(destination)
    }

    private var formattedDownloadSize: String {
        guard let bytes = game.sizeEstimate?.downloadBytes, bytes > 0 else { return String(localized: .Library.notProvided) }
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
        if installationPlatform != .nativeMacOS {
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
        .frame(width: width, height: width * 9 / 16)
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
    let selection: StoreMediaSelection
    let game: StoreLibraryGame
    let onDismiss: () -> Void
    @State private var currentIndex: Int
    @State private var player = AVPlayer()
    @State private var isPlaying = false

    init(selection: StoreMediaSelection, game: StoreLibraryGame, onDismiss: @escaping () -> Void) {
        self.selection = selection
        self.game = game
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: min(max(selection.initialIndex, 0), max(selection.items.count - 1, 0)))
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(0.6, min((geometry.size.width - 48) / 910, (geometry.size.height - 48) / 682)))

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color(red: 0.015, green: 0.025, blue: 0.04).opacity(0.64))
                    .ignoresSafeArea()

                modalPanel
                    .scaleEffect(scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onAppear(perform: preparePlayer)
        .onChange(of: currentIndex) { preparePlayer() }
        .onDisappear { player.pause() }
        .onExitCommand { onDismiss() }
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

    private var modalPanel: some View {
        VStack(spacing: 0) {
            header
                .frame(width: 910, height: 76)
            mediaStage
                .frame(width: 910, height: 430)
            metadata
                .frame(width: 910, height: 50)
            Divider()
                .opacity(0.42)
                .padding(.horizontal, 28)
                .frame(width: 910, height: 1)
            filmstrip
                .frame(width: 910, height: 125)
        }
        .frame(width: 910, height: 682)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.14, blue: 0.17).opacity(0.72),
                            Color(red: 0.035, green: 0.045, blue: 0.06).opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.58), radius: 40, y: 20)
    }

    private var currentItem: StoreMediaItem {
        guard selection.items.indices.contains(currentIndex) else {
            return selection.items.first ?? .screenshot(URL(fileURLWithPath: "/"))
        }
        return selection.items[currentIndex]
    }

    private var header: some View {
        HStack(spacing: 12) {
            headerArtwork
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Media")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer(minLength: 20)
            Text("\(currentIndex + 1) / \(selection.items.count)")
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
                .padding(.trailing, 6)
            headerButton(title: "Fullscreen", symbol: "arrow.up.left.and.arrow.down.right", action: toggleFullscreen)
                .help("Fullscreen (⌘↩)")
            headerButton(title: "Close", symbol: "xmark", action: onDismiss)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .background {
            LinearGradient(
                colors: [.white.opacity(0.035), .black.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottom) { Divider().opacity(0.34) }
    }

    private var headerArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [.indigo, .cyan.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image = ArtworkImageCache.customImage(
                processedPath: game.customArtworkPath,
                originalPath: game.customArtworkOriginalPath
            ) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let path = game.artworkPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let value = game.portraitImageURL ?? game.headerImageURL, let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "gamecontroller.fill").foregroundStyle(.white.opacity(0.82))
                    }
                }
            } else {
                Image(systemName: "gamecontroller.fill").foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.18)) }
    }

    private func headerButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.08)) }
        .accessibilityLabel(title)
    }

    private var mediaStage: some View {
        ZStack {
            mediaBackdrop
            mediaContent
                .frame(maxWidth: 720, maxHeight: 392)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
            if selection.items.count > 1 {
                HStack {
                    galleryButton(title: "Previous media", symbol: "chevron.left", action: showPrevious)
                    Spacer()
                    galleryButton(title: "Next media", symbol: "chevron.right", action: showNext)
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.22))
        .clipped()
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
            .blur(radius: 36)
            .overlay(Color(red: 0.015, green: 0.035, blue: 0.055).opacity(0.58))
            .overlay(Color.black.opacity(0.34))
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(currentItem.isVideo ? "Video" : "Screenshot") \(currentIndex + 1) of \(selection.items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(currentItem.isVideo ? "Video" : "Image")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(currentItem.isVideo ? currentItem.title : game.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(game.developer ?? game.provider.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 30)
        .background(Color.black.opacity(0.08))
    }

    private var filmstrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 28) {
                ForEach(Array(selection.items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        currentIndex = index
                    } label: {
                        StoreMediaThumbnail(item: item, width: 146)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(index == currentIndex ? Color.accentColor : .white.opacity(0.12), lineWidth: index == currentIndex ? 3 : 1)
                            }
                            .shadow(color: index == currentIndex ? Color.accentColor.opacity(0.42) : .clear, radius: 4)
                            .opacity(index == currentIndex ? 1 : 0.76)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.accessibilityTitle)
                }
            }
            .padding(.horizontal, 28)
            .frame(minHeight: 124)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.opacity(0.12))
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
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.2)) }
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
