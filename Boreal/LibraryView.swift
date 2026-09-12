import AppKit
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum LibrarySort: String, CaseIterable, Sendable {
    case nameAscending, nameDescending, lastUsed, playtime, compatibility, installedFirst

    var title: LocalizedStringResource {
        switch self {
        case .nameAscending: .Library.sortNameAscending
        case .nameDescending: .Library.sortNameDescending
        case .lastUsed: .Library.sortLastUsed
        case .playtime: .Library.playtime
        case .compatibility: .Library.compatibilityTitle
        case .installedFirst: .Library.sortInstalledFirst
        }
    }

    var symbol: String {
        switch self {
        case .nameAscending: "textformat.abc"
        case .nameDescending: "textformat.abc.dottedunderline"
        case .lastUsed: "clock"
        case .playtime: "hourglass"
        case .compatibility: "checkmark.seal"
        case .installedFirst: "arrow.down.circle"
        }
    }
}

nonisolated enum LibraryGrouping: String, CaseIterable, Sendable {
    case source, availability, compatibility, none

    var title: LocalizedStringResource {
        switch self {
        case .source: .Library.source
        case .availability: .Library.availability
        case .compatibility: .Library.compatibilityTitle
        case .none:
            LocalizedStringResource("none", defaultValue: "None", table: "Library")
        }
    }
}

nonisolated enum LibrarySourceFilter: String, CaseIterable, Sendable {
    case boreal, steam, epic, gog

    var title: LocalizedStringResource {
        switch self {
        case .boreal: .Library.importedGames
        case .steam: .Library.steam
        case .epic: .Library.epicGames
        case .gog: .Library.gog
        }
    }

    var searchTitle: String {
        switch self {
        case .boreal: "Imported Games"
        case .steam: "Steam"
        case .epic: "Epic Games"
        case .gog: "GOG"
        }
    }

    var symbol: String {
        switch self {
        case .boreal: "square.grid.2x2"
        case .steam: "gamecontroller.fill"
        case .epic: "e.square.fill"
        case .gog: "g.square.fill"
        }
    }
}

nonisolated enum LibraryAvailabilityFilter: String, CaseIterable, Sendable {
    case installed, notInstalled, readyToPlay, recent, neverUsed, needsAttention

    var title: LocalizedStringResource {
        switch self {
        case .installed: .Library.installed
        case .notInstalled: .Library.notInstalled
        case .readyToPlay: .Library.readyToPlay
        case .recent: .Library.recentlyUsed
        case .neverUsed: .Library.neverUsed
        case .needsAttention: .Library.needsAttention
        }
    }
}

nonisolated enum LibraryCompatibilityFilter: String, CaseIterable, Sendable {
    case nativeMacOS, excellent, good, limited, unsupported, unknown

    var title: LocalizedStringResource {
        switch self {
        case .nativeMacOS: .Library.nativeMacOS
        case .excellent: .Compatibility.excellentTitle
        case .good: .Compatibility.goodTitle
        case .limited: .Compatibility.limitedTitle
        case .unsupported: .Compatibility.unsupportedTitle
        case .unknown: .Compatibility.unknownTitle
        }
    }

    var symbol: String {
        switch self {
        case .nativeMacOS: "apple.logo"
        case .excellent: "checkmark.seal.fill"
        case .good: "checkmark.circle.fill"
        case .limited: "exclamationmark.triangle.fill"
        case .unsupported: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

nonisolated enum LibraryStatus: String, Hashable, Sendable {
    case missingFiles, needsAttention, installerRunning, installerReady
    case ready, preparing, starting, running, installing, unavailable
    case installed, available

    var title: LocalizedStringResource {
        switch self {
        case .missingFiles: .Library.missingFiles
        case .needsAttention: .Library.needsAttention
        case .installerRunning: .Library.installerRunning
        case .installerReady: .Library.installerReady
        case .ready: .Library.ready
        case .preparing: .Library.preparing
        case .starting: .Library.starting
        case .running: .Library.running
        case .installing: .Library.installing
        case .unavailable: .Library.unavailable
        case .installed: .Library.installed
        case .available: .Library.available
        }
    }

    var searchTitle: String {
        switch self {
        case .missingFiles: "Missing files"
        case .needsAttention: "Needs Attention"
        case .installerRunning: "Installer running"
        case .installerReady: "Installer ready"
        case .ready: "Ready"
        case .preparing: "Preparing"
        case .starting: "Starting"
        case .running: "Running"
        case .installing: "Installing"
        case .unavailable: "Unavailable"
        case .installed: "Installed"
        case .available: "Available"
        }
    }

    static func application(_ status: ApplicationStatus, installerOnly: Bool) -> Self {
        if installerOnly {
            switch status {
            case .running: return .installerRunning
            case .ready: return .installerReady
            default: break
            }
        }

        switch status {
        case .ready: return .ready
        case .preparing: return .preparing
        case .starting: return .starting
        case .running: return .running
        case .installing: return .installing
        case .needsAttention: return .needsAttention
        case .unavailable: return .unavailable
        }
    }
}

nonisolated struct LibraryItem: Identifiable, Hashable, Sendable {
    nonisolated enum ID: Hashable, Sendable { case application(UUID), storeGame(UUID) }
    nonisolated enum Kind: Hashable, Sendable { case application(WindowsApplication), storeGame(StoreLibraryGame) }

    let id: ID
    let kind: Kind
    let name: String
    let subtitle: String
    let producer: String?
    let source: LibrarySourceFilter
    let isInstallerOnly: Bool
    let installed: Bool
    let readyToPlay: Bool
    let running: Bool
    let needsAttention: Bool
    let lastUsed: Date?
    let playtimeMinutes: Int?
    let storageBytes: Int64?
    let storageIsEstimate: Bool
    let supportsNativeMacOS: Bool
    let compatibility: CompatibilityRating
    let status: LibraryStatus

    var statusText: String { status.searchTitle }
    var localizedStatusText: LocalizedStringResource { status.title }

    var favoriteKey: String {
        switch kind {
        case .application(let app): "application:\(app.id.uuidString)"
        case .storeGame(let game): "\(game.provider.rawValue):\(game.externalID)"
        }
    }

    var searchText: String {
        [name, subtitle, source.searchTitle, isInstallerOnly ? "installer" : "", installed ? "installed" : "not installed", readyToPlay ? "ready to play" : "", needsAttention ? "needs attention" : "", compatibility.rawValue, status.searchTitle]
            .joined(separator: " ")
    }
}

nonisolated enum LibraryProjector {
    static func makeItems(
        applications: [WindowsApplication],
        storeGames: [StoreLibraryGame],
        installations: [GameInstallation] = []
    ) -> [LibraryItem] {
        let storeGamesByLink = Dictionary(
            storeGames.map { game in (storeLink(provider: game.provider, externalID: game.externalID), game) },
            uniquingKeysWith: { first, _ in first }
        )
        let linkedApplications = Dictionary(
            applications.compactMap { app -> (String, WindowsApplication)? in
                guard let provider = app.storeProvider, let externalID = app.storeExternalID else { return nil }
                return (storeLink(provider: provider, externalID: externalID), app)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let apps = applications.filter { app in
            guard !app.isSteamRuntimeHost else { return false }
            guard let provider = app.storeProvider, let externalID = app.storeExternalID else { return true }
            return storeGamesByLink[storeLink(provider: provider, externalID: externalID)] == nil
        }.map { app in
            let installationState = installations.first(where: { $0.gameID == app.id })?.state
            let blocksExecution = installationState.map { $0 != .installed } ?? false
            let isPresent = installationState?.representsAnInstallation ?? (app.status != .unavailable)
            return LibraryItem(
                id: .application(app.id), kind: .application(app), name: app.name, subtitle: app.publisher, producer: app.publisher,
                source: app.isInstallerOnly ? .boreal : (app.usesStoreMetadataOnly ? .boreal : (app.storeProvider.map(source) ?? .boreal)),
                isInstallerOnly: app.isInstallerOnly,
                installed: isPresent,
                readyToPlay: !app.isInstallerOnly && !blocksExecution && (app.status == .ready || app.status == .running),
                running: !blocksExecution && app.status == .running,
                needsAttention: app.status == .needsAttention || app.status == .unavailable || installationState == .missing || installationState == .volumeUnavailable || installationState == .broken,
                lastUsed: app.lastOpened, playtimeMinutes: nil, storageBytes: app.storageBytes > 0 ? app.storageBytes : nil,
                storageIsEstimate: false,
                supportsNativeMacOS: false,
                compatibility: app.compatibility,
                status: installationState == .missing
                    ? .missingFiles
                    : (installationState == .broken
                        ? .needsAttention
                        : .application(app.status, installerOnly: app.isInstallerOnly))
            )
        }
        // Store metadata remains the canonical presentation after installation.
        // The linked application contributes live runtime state without replacing
        // artwork, media, ratings, or the store detail route.
        let games = storeGames.map { game in
            let linkedApp = linkedApplications[storeLink(provider: game.provider, externalID: game.externalID)]
            let installation = installations.first { installation in
                installation.gameID == game.id
                    || installation.storeReference == game.storeReference
            }
            let installationState = installation?.state
            let preparationNeedsRepair = installation?.preparationState == .needsRepair || installation?.preparationState == .incompatible
            let preparationInProgress = installation?.preparationState == .preparing
            let preparationIsReady = installation?.preparationState == .ready
            // A stale application record must not make an uninstalled store game
            // look playable. Unavailable records remain visible through the store
            // game, but no longer contribute runtime state or installation truth.
            let usableLinkedApp = linkedApp.flatMap { $0.status == .unavailable ? nil : $0 }
            let installationIsPresent = installationState?.representsAnInstallation ?? false
            let installationIsMissing = installationState == .missing
            let installationIsUnavailable = installationState == .volumeUnavailable
            let installationBlocksExecution = installationState.map { $0 != .installed } ?? false
            // A canonical missing installation outranks stale application
            // status. The old linked app record can remain for diagnostics,
            // but it must not make the game appear runnable.
            let liveLinkedApp = installationBlocksExecution ? nil : usableLinkedApp
            let ready = liveLinkedApp.map {
                ($0.status == .ready || $0.status == .running)
                    && preparationIsReady
                    && !preparationNeedsRepair
            }
                ?? (game.provider == .steam && installationIsPresent && !installationIsMissing && !installationIsUnavailable && preparationIsReady)
            let running = liveLinkedApp?.status == .running
            let attention = liveLinkedApp?.status == .needsAttention || installationIsUnavailable || preparationNeedsRepair
            let installed = liveLinkedApp != nil || installationIsPresent
            let storageBytes = liveLinkedApp.flatMap { $0.storageBytes > 0 ? $0.storageBytes : nil }
                ?? installation?.installedSize
                ?? game.sizeEstimate?.installedBytes
            let compatibility = usableLinkedApp.flatMap { $0.compatibility == .unknown ? nil : $0.compatibility }
                ?? game.compatibility?.tier.rating
                ?? .unknown
            let displayName: String
            if let linkedApp, linkedApp.usesStoreMetadataOnly { displayName = linkedApp.name }
            else { displayName = game.name }
            let status: LibraryStatus
            if let liveLinkedApp {
                status = .application(liveLinkedApp.status, installerOnly: false)
            } else if installationIsMissing {
                status = .missingFiles
            } else if installationIsUnavailable {
                status = .needsAttention
            } else if installationState == .installing {
                status = .installing
            } else if preparationInProgress {
                status = .installing
            } else if installationState == .broken || attention {
                status = .needsAttention
            } else if running {
                status = .running
            } else if ready {
                status = .ready
            } else if installed {
                status = .installed
            } else {
                status = .available
            }
            return LibraryItem(
                id: .storeGame(game.id), kind: .storeGame(game), name: displayName,
                subtitle: [
                    game.developer ?? game.provider.rawValue,
                    game.resolvedEntitlementState == .accountDisconnected ? "Account disconnected · local files kept" : nil
                ].compactMap { $0 }.joined(separator: " · "),
                producer: game.developer,
                source: linkedApp?.usesStoreMetadataOnly == true ? .boreal : source(game.provider),
                isInstallerOnly: false,
                installed: installed, readyToPlay: ready, running: running, needsAttention: attention,
                lastUsed: liveLinkedApp?.lastOpened ?? game.lastPlayed, playtimeMinutes: game.playtimeMinutes,
                storageBytes: storageBytes,
                storageIsEstimate: usableLinkedApp == nil && game.storageBytes == nil && game.sizeEstimate?.installedBytes != nil,
                supportsNativeMacOS: game.supportsNativeMacOS == true,
                compatibility: compatibility,
                status: status
            )
        }
        return apps + games
    }

    private static func storeLink(provider: GameLibraryProvider, externalID: String) -> String {
        "\(provider.rawValue)|\(externalID)"
    }

    static func project(
        _ items: [LibraryItem], searchText: String, sources: Set<LibrarySourceFilter>,
        availability: Set<LibraryAvailabilityFilter>, compatibility: Set<LibraryCompatibilityFilter>,
        sort: LibrarySort, producer: String = "", favorites: Set<String> = [], favoritesOnly: Bool = false
    ) -> [LibraryItem] {
        let terms = normalized(searchText).split(separator: " ").map(String.init)
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return items.filter { item in
            let haystack = normalized(item.searchText)
            guard terms.allSatisfy(haystack.contains) else { return false }
            guard producer.isEmpty || matchesProducer(producer, item: item) else { return false }
            guard !favoritesOnly || favorites.contains(item.favoriteKey) else { return false }
            guard sources.isEmpty || sources.contains(item.source) else { return false }
            if !availability.isEmpty {
                let matches = availability.contains { filter in
                    switch filter {
                    case .installed: item.installed
                    case .notInstalled: !item.installed
                    case .readyToPlay: item.readyToPlay
                    case .recent: item.lastUsed.map { $0 >= recentCutoff } ?? false
                    case .neverUsed: item.lastUsed == nil
                    case .needsAttention: item.needsAttention
                    }
                }
                guard matches else { return false }
            }
            guard compatibility.isEmpty || compatibility.contains(compatibilityFilter(item)) else { return false }
            return true
        }
        .sorted { ordered($0, before: $1, by: sort) }
    }

    static func compatibilityFilter(_ rating: CompatibilityRating) -> LibraryCompatibilityFilter {
        switch rating {
        case .excellent: .excellent
        case .good: .good
        case .limited: .limited
        case .unsupported: .unsupported
        case .unknown: .unknown
        }
    }

    static func compatibilityFilter(_ item: LibraryItem) -> LibraryCompatibilityFilter {
        item.supportsNativeMacOS ? .nativeMacOS : compatibilityFilter(item.compatibility)
    }

    private static func source(_ provider: GameLibraryProvider) -> LibrarySourceFilter {
        switch provider {
        case .steam: .steam
        case .epic: .epic
        case .gog: .gog
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "ł", with: "l")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func matchesProducer(_ producer: String, item: LibraryItem) -> Bool {
        guard let itemProducer = item.producer else { return false }
        let wanted = normalized(producer)
        return normalized(itemProducer) == wanted
            || itemProducer
                .split { $0 == "," || $0 == ";" || $0 == "|" }
                .contains { normalized(String($0)) == wanted }
    }

    private static func ordered(_ lhs: LibraryItem, before rhs: LibraryItem, by sort: LibrarySort) -> Bool {
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        switch sort {
        case .nameAscending: return nameOrder == .orderedAscending
        case .nameDescending: return nameOrder == .orderedDescending
        case .lastUsed:
            if lhs.lastUsed != rhs.lastUsed { return (lhs.lastUsed ?? .distantPast) > (rhs.lastUsed ?? .distantPast) }
        case .playtime:
            if lhs.playtimeMinutes != rhs.playtimeMinutes { return (lhs.playtimeMinutes ?? -1) > (rhs.playtimeMinutes ?? -1) }
        case .compatibility:
            if rank(lhs.compatibility) != rank(rhs.compatibility) { return rank(lhs.compatibility) > rank(rhs.compatibility) }
        case .installedFirst:
            if lhs.installed != rhs.installed { return lhs.installed }
        }
        return nameOrder == .orderedAscending
    }

    private static func rank(_ rating: CompatibilityRating) -> Int {
        switch rating {
        case .excellent: 4
        case .good: 3
        case .limited: 2
        case .unknown: 1
        case .unsupported: 0
        }
    }
}

struct LibraryToolbarControls: View {
    @Binding var style: ContentView.LibraryStyle
    @Binding var sort: LibrarySort
    @Binding var grouping: LibraryGrouping
    @Binding var sourceFilters: String
    @Binding var availabilityFilters: String
    @Binding var compatibilityFilters: String

    private var filterCount: Int {
        rawSet(sourceFilters, as: LibrarySourceFilter.self).count
            + rawSet(availabilityFilters, as: LibraryAvailabilityFilter.self).count
            + rawSet(compatibilityFilters, as: LibraryCompatibilityFilter.self).count
    }

    var body: some View {
        Menu {
            Menu(.Library.sortBy, systemImage: "arrow.up.arrow.down") {
                ForEach(LibrarySort.allCases, id: \.self) { value in
                    Button { sort = value } label: {
                        Label(value.title, systemImage: sort == value ? "checkmark" : value.symbol)
                    }
                }
            }
            Menu(.Library.groupBy, systemImage: "rectangle.3.group") {
                ForEach(LibraryGrouping.allCases, id: \.self) { value in
                    Button { grouping = value } label: {
                        Label(value.title, systemImage: grouping == value ? "checkmark" : "rectangle.3.group")
                    }
                }
            }
            Divider()
            Section(.Library.source) {
                ForEach(LibrarySourceFilter.allCases, id: \.self) { filterButton($0, title: $0.title, raw: $sourceFilters) }
            }
            Section(.Library.availability) {
                ForEach(LibraryAvailabilityFilter.allCases, id: \.self) { filterButton($0, title: $0.title, raw: $availabilityFilters) }
            }
            Section(.Library.compatibilityTitle) {
                ForEach(LibraryCompatibilityFilter.allCases, id: \.self) { filterButton($0, title: $0.title, raw: $compatibilityFilters) }
            }
            if filterCount > 0 {
                Divider()
                Button(.Library.clearFilters, systemImage: "xmark.circle") { clearFilters() }
            }
        } label: {
            Label(
                filterCount == 0 ? .Library.viewOptions : .Library.viewOptionsCount(filterCount),
                systemImage: "slider.horizontal.3"
            )
        }
        .help(Text(.Library.sortGroupFilterHelp))

        Picker(.Library.viewLayout, selection: $style) {
            Label(.Library.grid, systemImage: "square.grid.2x2").tag(ContentView.LibraryStyle.grid)
            Label(.Library.list, systemImage: "list.bullet").tag(ContentView.LibraryStyle.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 86)
    }

    @ViewBuilder private func filterButton<Value>(_ value: Value, title: LocalizedStringResource, raw: Binding<String>) -> some View where Value: RawRepresentable & Hashable, Value.RawValue == String {
        let selected = rawSet(raw.wrappedValue, as: Value.self).contains(value)
        Button {
            var values = rawSet(raw.wrappedValue, as: Value.self)
            if selected { values.remove(value) } else { values.insert(value) }
            raw.wrappedValue = serialized(values)
        } label: { Label(title, systemImage: selected ? "checkmark" : "circle") }
    }

    private func clearFilters() {
        sourceFilters = ""
        availabilityFilters = ""
        compatibilityFilters = ""
    }
}

struct LibraryView: View {
    @Environment(BorealStore.self) private var store
    @Binding var searchText: String
    let style: ContentView.LibraryStyle
    let sort: LibrarySort
    let grouping: LibraryGrouping
    @Binding var sourceFilters: String
    @Binding var availabilityFilters: String
    @Binding var compatibilityFilters: String
    @Binding var producerFilter: String
    let favoritesOnly: Bool
    let installAction: () -> Void
    let syncSteamAction: () -> Void
    let importAction: (URL) -> Void
    let selectAction: (UUID) -> Void
    let selectStoreGameAction: (UUID) -> Void
    let selectDiscoveryGameAction: (AppleGamingWikiGame) -> Void
    @AppStorage("developerMode") private var developerMode = false
    @State private var removeCandidate: WindowsApplication?
    @State private var uninstallCandidate: StoreLibraryGame?
    @State private var projectedLibrary = LibraryProjectionCache()

    private var allItems: [LibraryItem] {
        projectedLibrary.items(
            applications: store.applications,
            storeGames: store.storeGames,
            installations: store.installations
        )
    }

    private var items: [LibraryItem] {
        LibraryProjector.project(
            allItems, searchText: searchText,
            sources: rawSet(sourceFilters, as: LibrarySourceFilter.self),
            availability: rawSet(availabilityFilters, as: LibraryAvailabilityFilter.self),
            compatibility: rawSet(compatibilityFilters, as: LibraryCompatibilityFilter.self),
            sort: sort, producer: producerFilter,
            favorites: favoritesOnly ? store.favoriteKeys : [], favoritesOnly: favoritesOnly
        )
    }

    private var activeFilters: [ActiveLibraryFilter] {
        (producerFilter.isEmpty ? [] : [ActiveLibraryFilter(id: "producer", title: .Library.producerFilter(producerFilter)) {
            producerFilter = ""
        }]) + rawSet(availabilityFilters, as: LibraryAvailabilityFilter.self).map { value in
            ActiveLibraryFilter(id: "availability:\(value.rawValue)", title: value.title) { toggle(value, raw: $availabilityFilters) }
        } + rawSet(compatibilityFilters, as: LibraryCompatibilityFilter.self).map { value in
            ActiveLibraryFilter(id: "compatibility:\(value.rawValue)", title: value.title) { toggle(value, raw: $compatibilityFilters) }
        }
    }

    private var selectedSources: Set<LibrarySourceFilter> {
        rawSet(sourceFilters, as: LibrarySourceFilter.self)
    }

    private var selectedCompatibility: Set<LibraryCompatibilityFilter> {
        rawSet(compatibilityFilters, as: LibraryCompatibilityFilter.self)
    }

    private var compatibilityCountItems: [LibraryItem] {
        selectedSources.isEmpty ? allItems : allItems.filter { selectedSources.contains($0.source) }
    }

    private var showsSavedDiscoveryGames: Bool {
        !store.savedDiscoveryGames.isEmpty && !favoritesOnly && sourceFilters.isEmpty
            && availabilityFilters.isEmpty && compatibilityFilters.isEmpty && producerFilter.isEmpty
    }

    private var hasActiveRefinement: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedSources.isEmpty
            || !activeFilters.isEmpty
            || favoritesOnly
    }

    private var discoveryProducerGames: [AppleGamingWikiGame] {
        guard !producerFilter.isEmpty else { return [] }
        let ownedSteamIDs = Set(store.storeGames.filter { $0.provider == .steam }.map(\.externalID))
        let ownedNames = Set(allItems.map { normalizedName($0.name) })
        return store.discoveryGames(developer: producerFilter).filter { game in
            if let steamAppID = game.steamAppID, ownedSteamIDs.contains(steamAppID) { return false }
            return !ownedNames.contains(normalizedName(game.title))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsSavedDiscoveryGames { SavedDiscoveryGamesView(searchText: searchText) }
            if !allItems.isEmpty { quickFilters }
            if !activeFilters.isEmpty { activeFilterBar }
            if !producerFilter.isEmpty { discoveryProducerSection }
            Group {
                if allItems.isEmpty && showsSavedDiscoveryGames {
                    Spacer()
                } else if allItems.isEmpty && !favoritesOnly {
                    BorealEmptyState(action: installAction, steamAction: syncSteamAction)
                } else if items.isEmpty {
                    noResults
                } else if style == .grid {
                    grid
                } else {
                    table
                }
            }
        }
        .task(id: producerFilter) {
            await store.searchDiscoveryGames(developer: producerFilter)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, ["exe", "msi"].contains(url.pathExtension.lowercased()) else { return false }
            importAction(url)
            return true
        }
        .confirmationDialog(
            Text(.Library.removeApplication(removeCandidate?.name ?? "application")),
            isPresented: Binding(get: { removeCandidate != nil }, set: { if !$0 { removeCandidate = nil } })
        ) {
            Button(.Library.removeAppAndEnvironment, role: .destructive) {
                if let id = removeCandidate?.id { store.removeApplication(id) }
                removeCandidate = nil
            }
            Button(.Library.cancel, role: .cancel) { removeCandidate = nil }
        } message: { Text(.Library.removeApplicationMessage) }
        .confirmationDialog(
            Text(.Library.uninstallGame(uninstallCandidate?.name ?? "game")),
            isPresented: Binding(get: { uninstallCandidate != nil }, set: { if !$0 { uninstallCandidate = nil } })
        ) {
            Button(.Library.uninstallGameAction, role: .destructive) {
                if let game = uninstallCandidate { store.uninstallStoreGame(game) }
                uninstallCandidate = nil
            }
            Button(.Library.cancel, role: .cancel) { uninstallCandidate = nil }
        } message: {
            Text(.Library.uninstallGameMessage)
        }
    }

    @ViewBuilder private var discoveryProducerSection: some View {
        if !discoveryProducerGames.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(.Library.moreFromDiscovery(producerFilter)).font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(discoveryProducerGames) { game in
                            DiscoveryGameTile(game: game, horizontal: true) {
                                selectDiscoveryGameAction(game)
                            }
                            .frame(width: 320)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        } else if store.discoveryProducerSearchState == .loading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(.Library.lookingForMoreGamesBy(producerFilter))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func normalizedName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var quickFilters: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    sourceButton(
                        title: .Library.all,
                        symbol: "square.grid.2x2",
                        count: allItems.count,
                        selected: selectedSources.isEmpty
                    ) {
                        sourceFilters = ""
                    }

                    ForEach(LibrarySourceFilter.allCases, id: \.self) { source in
                        let count = allItems.lazy.filter { $0.source == source }.count
                        sourceButton(
                            title: source.title,
                            symbol: source.symbol,
                            count: count,
                            selected: selectedSources.contains(source)
                        ) {
                            selectQuickSource(source)
                        }
                        .disabled(count == 0)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .background(.bar)
            Divider().opacity(0.55)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text(.Library.compatibilityTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    compatibilityButton(
                        title: .Library.all,
                        symbol: "circle.grid.2x2",
                        count: compatibilityCountItems.count,
                        selected: selectedCompatibility.isEmpty
                    ) {
                        compatibilityFilters = ""
                    }

                    ForEach(LibraryCompatibilityFilter.allCases, id: \.self) { value in
                        let count = compatibilityCountItems.lazy.filter {
                            LibraryProjector.compatibilityFilter($0) == value
                        }.count
                        compatibilityButton(
                            title: value.title,
                            symbol: value.symbol,
                            count: count,
                            selected: selectedCompatibility.contains(value)
                        ) {
                            selectQuickCompatibility(value)
                        }
                        .disabled(count == 0)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
            }
            .background(.bar)
            Divider()
        }
    }

    private func sourceButton(
        title: LocalizedStringResource,
        symbol: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let countAccessibilityLabel: LocalizedStringResource = .Library.sourceItemCount(count)

        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
                Text(count.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.055), in: Capsule())
            .overlay {
                Capsule().stroke(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(Text(count == 0 ? .Library.noItemsFromSource : .Library.showSourceItems))
        .accessibilityLabel(Text(countAccessibilityLabel))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectQuickSource(_ source: LibrarySourceFilter) {
        sourceFilters = selectedSources == [source] ? "" : serialized(Set([source]))
    }

    private func compatibilityButton(
        title: LocalizedStringResource,
        symbol: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let countAccessibilityLabel: LocalizedStringResource = .Library.compatibilityItemCount(count)

        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
                Text(count.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: Capsule())
            .overlay {
                Capsule().stroke(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(Text(count == 0 ? .Library.noGamesWithCompatibility : .Library.showCompatibilityGames))
        .accessibilityLabel(Text(countAccessibilityLabel))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectQuickCompatibility(_ value: LibraryCompatibilityFilter) {
        compatibilityFilters = selectedCompatibility == [value] ? "" : serialized(Set([value]))
    }

    private var activeFilterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activeFilters) { filter in
                        Button(action: filter.remove) {
                            Label(filter.title, systemImage: "xmark")
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                            .help(Text(.Library.removeFilter))
                    }
                    if activeFilters.count > 1 {
                        Button(.Library.clearAll) { clearFilters() }.font(.caption).buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
            }
            .background(.bar)
            Divider()
        }
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label(
                favoritesOnly ? .Library.noFavoritesYet : .Library.noMatchingItems,
                systemImage: favoritesOnly ? "heart" : "line.3.horizontal.decrease.circle"
            )
        } description: {
            Text(
                favoritesOnly
                    ? .Library.favoritesEmptyDescription
                    : (searchText.isEmpty
                        ? .Library.noItemsMatchSelectedFilters
                        : .Library.noItemsMatchSearch(searchText))
            )
        } actions: {
            if !favoritesOnly {
                Button(.Library.clearSearchAndFilters) { searchText = ""; clearFilters() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !hasActiveRefinement, !attentionItems.isEmpty { attentionSection }
                if !hasActiveRefinement, !recentItems.isEmpty { continuePlayingSection }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        if let title = group.title, showsHeader(for: group) {
                            HStack {
                                Text(title).font(.title3).fontWeight(.semibold)
                                Text(.Library.gameCount(group.items.count)).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if grouping == .source, let source = group.source { syncButton(for: source) }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 250), spacing: 28)], spacing: 28) {
                            ForEach(group.items) { item in gridItem(item) }
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var table: some View {
        Table(of: LibraryItem.self) {
            TableColumn(.Library.name, content: { (item: LibraryItem) in
                Button { select(item) } label: {
                    HStack(spacing: 9) {
                        itemIcon(item, compact: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).fontWeight(.medium).lineLimit(1)
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { itemContextMenu(item) }
            })
            .width(min: 220, ideal: 300)
            TableColumn(.Library.source, content: { (item: LibraryItem) in
                Label(item.source.title, systemImage: item.source.symbol).foregroundStyle(.secondary)
            })
            .width(min: 90, ideal: 120)
            TableColumn(.Library.status, content: { (item: LibraryItem) in
                Label(item.localizedStatusText, systemImage: statusSymbol(item)).foregroundStyle(statusColor(item))
            })
            .width(min: 105, ideal: 135)
            TableColumn(.Library.compatibilityTitle, content: { (item: LibraryItem) in
                if item.supportsNativeMacOS {
                    NativeMacOSBadge(compact: true)
                } else {
                    CompatibilityLabel(rating: item.compatibility)
                }
            })
                .width(min: 115, ideal: 145)
            TableColumn(.Library.lastUsed, content: { (item: LibraryItem) in
                if let lastUsed = item.lastUsed {
                    Text(lastUsed, format: Date.FormatStyle(date: .abbreviated))
                        .foregroundStyle(.primary)
                } else {
                    Text(.Library.never).foregroundStyle(.secondary)
                }
            })
            .width(min: 90, ideal: 110)
            TableColumn(.Library.playtime, content: { (item: LibraryItem) in
                Text(playtime(item.playtimeMinutes)).foregroundStyle(item.playtimeMinutes == nil ? .tertiary : .secondary)
            })
            .width(min: 70, ideal: 85)
        } rows: {
            ForEach(items) { item in
                TableRow(item)
            }
        }
    }

    private var groups: [LibraryGroup] {
        switch grouping {
        case .none:
            [LibraryGroup(id: "all", title: nil, source: nil, items: items)]
        case .source:
            LibrarySourceFilter.allCases.compactMap { source in
                let values = items.filter { $0.source == source }
                return values.isEmpty ? nil : LibraryGroup(id: source.rawValue, title: source.title, source: source, items: values)
            }
        case .availability:
            [
                ("needsAttention", .Library.needsAttention, { (item: LibraryItem) in item.needsAttention }),
                ("readyToPlay", .Library.readyToPlay, { (item: LibraryItem) in !item.needsAttention && item.readyToPlay }),
                ("installed", .Library.installed, { (item: LibraryItem) in !item.needsAttention && !item.readyToPlay && item.installed }),
                ("available", .Library.available, { (item: LibraryItem) in !item.installed })
            ].compactMap { id, title, matches in
                let values = items.filter(matches)
                return values.isEmpty ? nil : LibraryGroup(id: id, title: title, source: nil, items: values)
            }
        case .compatibility:
            LibraryCompatibilityFilter.allCases.compactMap { value in
                let values = items.filter { LibraryProjector.compatibilityFilter($0) == value }
                return values.isEmpty ? nil : LibraryGroup(id: value.rawValue, title: value.title, source: nil, items: values)
            }
        }
    }

    private var attentionItems: [LibraryItem] {
        Array(allItems.filter(\.needsAttention).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(4))
    }

    private var recentItems: [LibraryItem] {
        Array(
            allItems
                .filter { $0.lastUsed != nil && !$0.needsAttention }
                .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
                .prefix(5)
        )
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(.Library.needsAttention, systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(spacing: 0) {
                ForEach(Array(attentionItems.enumerated()), id: \.element.id) { index, item in
                    Button { select(item) } label: {
                        HStack(spacing: 12) {
                            itemIcon(item, compact: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).fontWeight(.medium)
                                Text(item.localizedStatusText).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(11)
                    }
                    .buttonStyle(.plain)
                    if index < attentionItems.count - 1 { Divider().padding(.leading, 55) }
                }
            }
            .background(.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.orange.opacity(0.18)) }
        }
    }

    private var continuePlayingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(.Library.jumpBackIn).font(.title2.weight(.bold))
                Text(.Library.yourMostRecentGames).font(.callout).foregroundStyle(.secondary)
            }

            if let featured = recentItems.first {
                HStack(alignment: .top, spacing: 18) {
                    featuredCard(featured)
                    VStack(spacing: 8) {
                        ForEach(Array(recentItems.dropFirst().prefix(4))) { item in
                            recentRow(item)
                        }
                    }
                    .frame(width: 250)
                }
            }
        }
    }

    private func featuredCard(_ item: LibraryItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            featuredArtwork(item)
            LinearGradient(
                colors: [.clear, .black.opacity(0.32), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(.Library.continuePlaying, systemImage: "clock.arrow.circlepath")
                        .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.white.opacity(0.78))
                    Text(item.name).font(.title2.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                    featuredMetadata(item).font(.callout).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button(quickActionTitle(item), systemImage: quickActionSymbol(item)) { quickAction(item) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, minHeight: 230, maxHeight: 230)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { select(item) }
        .accessibilityLabel(Text(.Library.continueGame(item.name)))
    }

    private func recentRow(_ item: LibraryItem) -> some View {
        Button { select(item) } label: {
            HStack(spacing: 11) {
                itemIcon(item, compact: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.callout.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: item.source.symbol)
                        relativeDate(item.lastUsed)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func featuredArtwork(_ item: LibraryItem) -> some View {
        switch item.kind {
        case .application(let app):
            if let path = app.customArtworkPath, let image = ArtworkImageCache.image(at: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.indigo.opacity(0.9), .cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay { Image(systemName: app.iconSymbol).font(.system(size: 92)).foregroundStyle(.white.opacity(0.22)) }
            }
        case .storeGame(let game):
            if let path = game.customArtworkPath ?? game.artworkPath, let image = ArtworkImageCache.image(at: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let value = game.backgroundImageURL ?? game.headerImageURL ?? game.portraitImageURL,
                      let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { LinearGradient(colors: [.indigo, .cyan.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing) }
                }
            } else {
                LinearGradient(colors: [.indigo, .cyan.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    @ViewBuilder private func featuredMetadata(_ item: LibraryItem) -> some View {
        HStack(spacing: 0) {
            Text(item.source.title)
            if item.playtimeMinutes != nil {
                Text("  •  ")
                Text(playtime(item.playtimeMinutes))
            }
            Text("  •  ")
            Text(item.localizedStatusText)
        }
    }

    @ViewBuilder private func relativeDate(_ date: Date?) -> some View {
        if let date {
            Text(date, style: .relative)
        } else {
            Text(.Library.notPlayedYet)
        }
    }

    private func showsHeader(for group: LibraryGroup) -> Bool {
        grouping != .none && !(grouping == .source && groups.count == 1)
    }

    private func gridItem(_ item: LibraryItem) -> some View {
        LibraryGridHoverContainer { hovering in
            ZStack {
                libraryCardArtwork(item)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.28),
                        .init(color: .black.opacity(0.32), location: 0.52),
                        .init(color: .black.opacity(0.94), location: 0.76)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Label(item.localizedStatusText, systemImage: statusSymbol(item))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor(item))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.58), in: Capsule())
                        Spacer(minLength: 8)
                        favoriteButton(for: item)
                    }

                    Spacer(minLength: 40)

                    Button { select(item) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.name)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Label(item.source.title, systemImage: item.source.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))

                            HStack(spacing: 8) {
                                Label(
                                    item.readyToPlay ? .Library.installed : item.localizedStatusText,
                                    systemImage: item.readyToPlay ? "checkmark.circle.fill" : statusSymbol(item)
                                )
                                    .foregroundStyle(item.readyToPlay ? .green : statusColor(item))
                                Spacer(minLength: 4)
                                if let storageBytes = item.storageBytes, storageBytes > 0 {
                                    Label(
                                        "\(item.storageIsEstimate ? "≈ " : "")\(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))",
                                        systemImage: "internaldrive.fill"
                                    )
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.72))
                                }
                            }
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if hovering {
                        HStack(spacing: 14) {
                            Button(quickActionTitle(item), systemImage: quickActionSymbol(item)) { quickAction(item) }
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .buttonStyle(.plain)

                            Menu {
                                itemContextMenu(item)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.callout.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(.white.opacity(0.12), in: Circle())
                                    .overlay { Circle().stroke(.white.opacity(0.12), lineWidth: 1) }
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 36, height: 36)
                        }
                        .padding(.top, 11)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(12)
            }
            .aspectRatio(0.82, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(hovering ? Color.accentColor : .white.opacity(0.15), lineWidth: hovering ? 3 : 1)
            }
            .shadow(color: hovering ? Color.accentColor.opacity(0.24) : .black.opacity(0.24), radius: hovering ? 14 : 9, y: 5)
            .scaleEffect(hovering ? 1.012 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contextMenu { itemContextMenu(item) }
            .accessibilityLabel(
                Text(item.name) + Text(", ") + Text(item.source.title) + Text(", ") + Text(item.localizedStatusText)
            )
        }
    }

    @ViewBuilder private func libraryCardArtwork(_ item: LibraryItem) -> some View {
        switch item.kind {
        case .application(let app):
            if let path = app.customArtworkPath, let image = ArtworkImageCache.image(at: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(
                    colors: [.indigo.opacity(0.95), .cyan.opacity(0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: app.iconSymbol)
                        .font(.system(size: 86, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
        case .storeGame(let game):
            GeometryReader { geometry in
                GameArtworkView(
                    game: game,
                    width: geometry.size.width,
                    height: geometry.size.height
                )
            }
        }
    }

    private func favoriteButton(for item: LibraryItem) -> some View {
        let favorite = store.isFavorite(key: item.favoriteKey)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                store.toggleFavorite(key: item.favoriteKey)
            }
        } label: {
            ZStack {
                Image(systemName: "heart")
                    .foregroundStyle(.white)
                    .opacity(favorite ? 0 : 1)
                    .scaleEffect(favorite ? 0.7 : 1)
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .opacity(favorite ? 1 : 0)
                    .scaleEffect(favorite ? 1.16 : 0.55)
            }
            .font(.title3.weight(.semibold))
            .shadow(color: .black.opacity(0.7), radius: 3)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.34), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(0)
        .contentShape(Circle())
        .help(Text(favorite ? .Library.removeFromFavorites : .Library.addToFavorites))
        .accessibilityLabel(Text(favorite ? .Library.removeItemFromFavorites(item.name) : .Library.addItemToFavorites(item.name)))
        .accessibilityAddTraits(favorite ? .isSelected : [])
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: favorite)
    }

    @ViewBuilder private func itemIcon(_ item: LibraryItem, compact: Bool) -> some View {
        switch item.kind {
        case .application(let app):
            if let path = app.customArtworkPath, let image = ArtworkImageCache.image(at: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: compact ? 32 : 92, height: compact ? 42 : 92)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 14, style: .continuous))
            } else {
                AppIconView(symbol: app.iconSymbol, size: compact ? 32 : 92)
            }
        case .storeGame(let game): GameArtworkView(game: game, width: compact ? 32 : 148, height: compact ? 42 : 207)
        }
    }

    @ViewBuilder private func itemContextMenu(_ item: LibraryItem) -> some View {
        switch item.kind {
        case .application(let app):
            appContextMenu(app)
            Divider()
            customArtworkMenu(for: item)
        case .storeGame:
            if item.readyToPlay || item.running {
                Button(quickActionTitle(item), systemImage: quickActionSymbol(item)) { quickAction(item) }
                Divider()
            }
            Button(.Library.showDetails, systemImage: "info.circle") { select(item) }
            Divider()
            customArtworkMenu(for: item)
            if case .storeGame(let game) = item.kind,
               store.isInstalled(game),
               [.epic, .gog].contains(game.provider) {
                Divider()
                Button(.Library.uninstall, systemImage: "trash", role: .destructive) {
                    uninstallCandidate = game
                }
            }
        }
    }

    @ViewBuilder private func customArtworkMenu(for item: LibraryItem) -> some View {
        Button("Choose Custom Cover…", systemImage: "photo.on.rectangle") {
            chooseCustomArtwork(for: item)
        }
        if itemHasCustomArtwork(item) {
            Button("Restore Default Cover", systemImage: "arrow.uturn.backward") {
                resetCustomArtwork(for: item)
            }
        }
    }

    private func itemHasCustomArtwork(_ item: LibraryItem) -> Bool {
        switch item.kind {
        case .application(let application): application.customArtworkPath != nil
        case .storeGame(let game): game.customArtworkPath != nil
        }
    }

    private func chooseCustomArtwork(for item: LibraryItem) {
        let panel = NSOpenPanel()
        panel.title = "Choose Custom Cover"
        panel.message = "Select an image to use as this game's cover."
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() } }
        switch item.kind {
        case .application(let application):
            store.setCustomArtwork(from: sourceURL, for: application.id)
        case .storeGame(let game):
            store.setCustomArtwork(from: sourceURL, forStoreGameID: game.id)
        }
    }

    private func resetCustomArtwork(for item: LibraryItem) {
        switch item.kind {
        case .application(let application):
            store.resetCustomArtwork(for: application.id)
        case .storeGame(let game):
            store.resetCustomArtwork(forStoreGameID: game.id)
        }
    }

    @ViewBuilder private func syncButton(for source: LibrarySourceFilter) -> some View {
        if let provider = provider(source) {
            if libraryIsSyncing(provider) {
                ProgressView().controlSize(.small).help(Text(.Library.importingLibrary(provider.rawValue)))
            } else {
                Button(.Library.refresh, systemImage: "arrow.clockwise") {
                    store.syncLibrary(provider)
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help(Text(.Library.refreshLibrary))
            }
        }
    }

    private func provider(_ source: LibrarySourceFilter) -> GameLibraryProvider? {
        switch source {
        case .boreal: nil
        case .steam: .steam
        case .epic: .epic
        case .gog: .gog
        }
    }

    private func libraryIsSyncing(_ provider: GameLibraryProvider) -> Bool {
        store.isLibrarySyncing(provider)
    }

    private func select(_ item: LibraryItem) {
        switch item.id {
        case .application(let id): selectAction(id)
        case .storeGame(let id): selectStoreGameAction(id)
        }
    }

    private func quickAction(_ item: LibraryItem) {
        switch item.kind {
        case .application(let app):
            if app.status == .needsAttention || app.status == .unavailable || app.status.isBusy {
                selectAction(app.id)
            } else {
                store.toggleRunning(app.id)
            }
        case .storeGame(let game):
            if let app = store.linkedApplication(for: game) {
                if app.status == .needsAttention || app.status == .unavailable || app.status.isBusy {
                    selectStoreGameAction(game.id)
                } else {
                    store.toggleRunning(app.id)
                }
            } else if game.provider == .steam, store.isInstalled(game),
                      let url = URL(string: "steam://rungameid/\(game.externalID)") {
                NSWorkspace.shared.open(url)
            } else {
                selectStoreGameAction(game.id)
            }
        }
    }

    private func quickActionTitle(_ item: LibraryItem) -> LocalizedStringResource {
        if item.running { return .Library.stop }
        if item.needsAttention { return .Library.details }
        if item.isInstallerOnly { return .Library.runInstaller }
        if item.readyToPlay { return .Library.play }
        if item.installed { return .Library.prepare }
        return .Library.install
    }

    private func quickActionSymbol(_ item: LibraryItem) -> String {
        if item.running { return "stop.fill" }
        if item.needsAttention { return "exclamationmark.triangle.fill" }
        if item.isInstallerOnly { return "shippingbox.fill" }
        if item.readyToPlay { return "play.fill" }
        if item.installed { return "wand.and.stars" }
        return "arrow.down.circle.fill"
    }

    private func statusSymbol(_ item: LibraryItem) -> String {
        if item.needsAttention { return "exclamationmark.triangle.fill" }
        if item.running { return "circle.fill" }
        if item.isInstallerOnly { return "shippingbox.fill" }
        if item.readyToPlay { return "play.circle.fill" }
        if item.installed { return "checkmark.circle.fill" }
        return "icloud.and.arrow.down"
    }

    private func statusColor(_ item: LibraryItem) -> Color {
        if item.needsAttention { return .orange }
        if item.readyToPlay { return .green }
        return .secondary
    }

    private func playtime(_ minutes: Int?) -> LocalizedStringResource {
        guard let minutes else { return .Library.emDash }
        if minutes == 0 { return .Library.notPlayed }
        if minutes < 60 { return .Library.playtimeMinutesValue(minutes) }
        let hours = (Double(minutes) / 60).formatted(.number.precision(.fractionLength(1)))
        return .Library.playtimeHoursValue(hours)
    }

    private func clearFilters() {
        sourceFilters = ""
        availabilityFilters = ""
        compatibilityFilters = ""
        producerFilter = ""
    }

    private func toggle<Value>(_ value: Value, raw: Binding<String>) where Value: RawRepresentable & Hashable, Value.RawValue == String {
        var values = rawSet(raw.wrappedValue, as: Value.self)
        if values.contains(value) { values.remove(value) } else { values.insert(value) }
        raw.wrappedValue = serialized(values)
    }

    @ViewBuilder private func appContextMenu(_ app: WindowsApplication) -> some View {
        if app.status == .running {
            Button(.Library.stop, systemImage: "stop.fill") { store.toggleRunning(app.id) }
        } else if app.status == .needsAttention {
            Button(.Library.tryAgain, systemImage: "arrow.clockwise") { store.retry(app.id) }
        } else {
            Button(app.isInstallerOnly ? .Library.runInstaller : .Library.open, systemImage: "play.fill") { store.toggleRunning(app.id) }
                .disabled(app.status.isBusy || app.status == .unavailable)
        }
        Divider()
        Button(.Library.showDetails, systemImage: "info.circle") { selectAction(app.id) }
        Button(.Library.showInFinder, systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.executablePath)])
        }
        if developerMode {
            Divider()
            if let environment = store.environment(id: app.environmentID) {
                Button(.Library.openCDrive, systemImage: "externaldrive") {
                    if let prefix = environment.prefixPath { NSWorkspace.shared.open(URL(fileURLWithPath: prefix).appending(path: "drive_c")) }
                }
                Button(.Library.viewLogs, systemImage: "doc.text.magnifyingglass") {
                    if let logs = environment.logsPath { NSWorkspace.shared.open(URL(fileURLWithPath: logs)) }
                }
            }
            if app.status == .running { Button(.Library.forceQuit, systemImage: "xmark.octagon", role: .destructive) { store.forceQuit(app.id) } }
        }
        Divider()
        Button(.Library.remove, systemImage: "trash", role: .destructive) { removeCandidate = app }
    }
}

private struct LibraryGroup: Identifiable {
    let id: String
    let title: LocalizedStringResource?
    let source: LibrarySourceFilter?
    let items: [LibraryItem]
}

private struct ActiveLibraryFilter: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let remove: () -> Void
}

@MainActor
private final class LibraryProjectionCache {
    private var applications: [WindowsApplication] = []
    private var storeGames: [StoreLibraryGame] = []
    private var installations: [GameInstallation] = []
    private var cachedItems: [LibraryItem] = []

    func items(
        applications: [WindowsApplication],
        storeGames: [StoreLibraryGame],
        installations: [GameInstallation]
    ) -> [LibraryItem] {
        guard applications != self.applications || storeGames != self.storeGames || installations != self.installations else { return cachedItems }
        self.applications = applications
        self.storeGames = storeGames
        self.installations = installations
        cachedItems = LibraryProjector.makeItems(applications: applications, storeGames: storeGames, installations: installations)
        return cachedItems
    }
}

private struct LibraryGridHoverContainer<Content: View>: View {
    @State private var hovering = false
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(hovering)
            .onHover { value in
                guard value != hovering else { return }
                withAnimation(.easeOut(duration: 0.14)) { hovering = value }
            }
    }
}

private func rawSet<Value>(_ raw: String, as type: Value.Type) -> Set<Value> where Value: RawRepresentable & Hashable, Value.RawValue == String {
    Set(raw.split(separator: ",").compactMap { Value(rawValue: String($0)) })
}

private func serialized<Value>(_ values: Set<Value>) -> String where Value: RawRepresentable, Value.RawValue == String {
    values.map(\.rawValue).sorted().joined(separator: ",")
}
