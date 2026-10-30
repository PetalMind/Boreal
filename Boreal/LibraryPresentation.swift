import Foundation

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
    nonisolated enum ID: Hashable, Sendable {
        case application(UUID)
        case storeGame(UUID)
    }
    nonisolated enum Kind: Hashable, Sendable {
        case application(WindowsApplication)
        case storeGame(StoreLibraryGame)
    }

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

    var localizedCompatibilityText: LocalizedStringResource {
        if supportsNativeMacOS { return .Compatibility.nativeTitle }
        return compatibility == .unknown ? .Library.notProvided : compatibility.localizedTitle
    }

    var favoriteKey: String {
        switch kind {
        case .application(let app): "application:\(app.id.uuidString)"
        case .storeGame(let game): "\(game.provider.rawValue):\(game.externalID)"
        }
    }

    var searchText: String {
        [
            name, subtitle, source.searchTitle, isInstallerOnly ? "installer" : "", installed ? "installed" : "not installed",
            readyToPlay ? "ready to play" : "", needsAttention ? "needs attention" : "", compatibility.rawValue, status.searchTitle,
        ]
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
                needsAttention: app.status == .needsAttention || app.status == .unavailable || installationState == .missing
                    || installationState == .volumeUnavailable || installationState == .broken,
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
            let ready =
                liveLinkedApp.map {
                    ($0.status == .ready || $0.status == .running)
                        && preparationIsReady
                        && !preparationNeedsRepair
                }
                ?? (game.provider == .steam && installationIsPresent && !installationIsMissing && !installationIsUnavailable && preparationIsReady)
            let running = liveLinkedApp?.status == .running
            let attention = liveLinkedApp?.status == .needsAttention || installationIsUnavailable || preparationNeedsRepair
            let installed = liveLinkedApp != nil || installationIsPresent
            let storageBytes =
                liveLinkedApp.flatMap { $0.storageBytes > 0 ? $0.storageBytes : nil }
                ?? installation?.installedSize
                ?? game.sizeEstimate?.installedBytes
            let compatibility =
                usableLinkedApp.flatMap { $0.compatibility == .unknown ? nil : $0.compatibility }
                ?? game.compatibility?.tier.rating
                ?? .unknown
            let displayName: String
            if let linkedApp, linkedApp.usesStoreMetadataOnly { displayName = linkedApp.name } else { displayName = game.name }
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
                    game.resolvedEntitlementState == .accountDisconnected ? "Account disconnected · local files kept" : nil,
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
