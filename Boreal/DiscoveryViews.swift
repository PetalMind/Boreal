import AppKit
import SwiftUI

struct DiscoveryView: View {
    @Environment(BorealStore.self) private var store
    @Binding var searchText: String
    let selectGame: (AppleGamingWikiGame) -> Void
    @State private var scope: DiscoveryScope = .all
    @State private var windowsMethod: AppleGamingWikiPlatform = .all
    @State private var genre = "All genres"
    @State private var rating = "All ratings"
    @State private var storefront = "All stores"
    @State private var sortOrder = "Recommended"
    @State private var hasCompatibilityReportOnly = false
    @AppStorage("discoveryListLayout") private var listLayout = false
    @State private var showGuide = false
    @State private var projection = DiscoveryProjection()
    @State private var page = 0
    @State private var pageInput = "1"
    private let pageSize = 60
    private let macProfile = DiscoveryMacProfile.current

    private var projectionRequest: DiscoveryProjectionRequest {
        DiscoveryProjectionRequest(
            revision: store.discoveryCatalogRevision,
            filters: DiscoveryFilters(
                scope: scope, windowsMethod: windowsMethod, genre: genre, rating: rating,
                storefront: storefront, sortOrder: sortOrder,
                hasCompatibilityReportOnly: hasCompatibilityReportOnly, query: query
            ))
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(1, min(1600, geometry.size.width - 40))
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                        header
                        if let catalog = store.discoveryCatalog {
                            catalogSummary(catalog)
                            Section {
                                if !query.isEmpty, let message = store.discoverySearchMessage {
                                    Label(message, systemImage: "magnifyingglass")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                if let notice = catalog.sourceNotice {
                                    Label(LocalizedStringKey(notice), systemImage: "info.circle")
                                        .font(.callout).foregroundStyle(.secondary)
                                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                }
                                if case .failed(let message) = store.discoveryState {
                                    Label(message, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
                                }
                                if query.isEmpty && scope == .recommended && projection.filters == projectionRequest.filters && !projection.recommended.isEmpty
                                {
                                    recommended(projection.recommended, width: contentWidth)
                                }
                                catalogContent(catalog, width: contentWidth)
                            } header: {
                                filters(catalog, width: contentWidth)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.08)))
                                    .id("discovery-results")
                            }
                        } else {
                            ContentUnavailableView {
                                Label(.Navigation.discoveryTitle, systemImage: "gamecontroller")
                            } description: {
                                if case .failed(let message) = store.discoveryState { Text(message) } else { ProgressView("Loading catalog…") }
                            } actions: {
                                Button("Retry") { store.refreshDiscoveryCatalog() }.disabled(store.discoveryState == .loading)
                            }
                        }
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .onChange(of: projectionRequest.filters) { _, _ in
                    page = 0
                    scrollProxy.scrollTo("discovery-results", anchor: .top)
                }
                .onChange(of: page) { _, value in
                    pageInput = String(value + 1)
                    scrollProxy.scrollTo("discovery-results", anchor: .top)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { if store.discoveryCatalog == nil { store.loadDiscoveryCatalog() } }
        .task(id: projectionRequest) {
            guard let catalog = store.discoveryCatalog else { return }
            let request = projectionRequest
            if request.filters.query != projection.filters?.query && !request.filters.query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            }
            let work = Task.detached(priority: .userInitiated) { request.filters.project(catalog) }
            let prepared = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            guard !Task.isCancelled, request == projectionRequest else { return }
            projection = prepared
            page = min(page, max(0, (prepared.games.count - 1) / pageSize))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.discoveryState == .loading {
                    ProgressView("Loading catalog…").controlSize(.small)
                } else {
                    Button("Refresh Discovery", systemImage: "arrow.clockwise") { store.refreshDiscoveryCatalog() }
                }
            }
        }
        .sheet(isPresented: $showGuide) {
            VStack {
                guide
                Button("Done") { showGuide = false }.keyboardShortcut(.cancelAction)
            }.padding(28).frame(width: 410)
        }
        .onChange(of: scope) { _, value in
            if value == .recommended { sortOrder = "Recommended" }
        }
        .task(id: query) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                store.clearDiscoverySearch()
                return
            }
            store.prepareDiscoverySearch(query)
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await store.searchDiscoveryGames(query)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(.Navigation.discoveryTitle)
                        .font(.title2.weight(.bold))
                    Text("Find games and check the best available way to play them on your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Data sources", systemImage: "info.circle") { showGuide = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("View Discovery data sources")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    macProfileLabel
                    Spacer(minLength: 8)
                    Text("Community catalog").font(.caption).foregroundStyle(.tertiary)
                }
                macProfileLabel
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [.accentColor.opacity(0.13), .accentColor.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.08)))
    }

    private var macProfileLabel: some View {
        Label(macProfile.summary, systemImage: "laptopcomputer")
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.08)))
    }

    private func catalogSummary(_ catalog: AppleGamingWikiCatalog) -> some View {
        let unknownCount = projection.unknownCount
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
            summaryStat(
                value: projection.trackedCount.formatted(),
                label: "games",
                symbol: "gamecontroller.fill"
            )
            summaryStat(
                value: projection.macSupportCount.formatted(),
                label: "Mac paths",
                symbol: "apple.logo"
            )
            if projection.trackedCount - unknownCount > 0 {
                summaryStat(
                    value: (projection.trackedCount - unknownCount).formatted(),
                    label: "games with reports",
                    symbol: "checkmark.seal"
                )
            }
            if unknownCount > 0 {
                summaryStat(value: unknownCount.formatted(), label: "without compatibility report", symbol: "questionmark.circle")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(projection.trackedCount) \(String(localized: "games")), "
                + "\(projection.macSupportCount) \(String(localized: "Mac paths")), "
                + "\(unknownCount) \(String(localized: "without compatibility report"))"
        )
    }

    private func summaryStat(value: String, label: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.callout.weight(.semibold))
                Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.05)))
    }

    private func filters(_ catalog: AppleGamingWikiCatalog, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Browse", selection: $scope) {
                ForEach(DiscoveryScope.allCases, id: \.self) { value in
                    Label(value.title, systemImage: value.symbol).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            if width >= 960 {
                HStack(spacing: 8) {
                    filterMenus(catalog)
                    Spacer(minLength: 8)
                    sortMenu
                    layoutPicker
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    filterMenus(catalog)
                    HStack {
                        Spacer(minLength: 0)
                        sortMenu
                        layoutPicker
                    }
                }
            }

            if hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if genre != "All genres" {
                            activeFilterChip(genre, reset: { genre = "All genres" })
                        }
                        if rating != "All ratings" {
                            activeFilterChip(
                                AppleGamingWikiRating(rawValue: rating)?.displayName ?? rating,
                                reset: { rating = "All ratings" }
                            )
                        }
                        if storefront != "All stores" {
                            activeFilterChip(storefront, reset: { storefront = "All stores" })
                        }
                        if scope == .windows, windowsMethod != .all {
                            activeFilterChip(windowsMethod.title, reset: { windowsMethod = .all })
                        }
                        if hasCompatibilityReportOnly {
                            activeFilterChip("Has compatibility report", reset: { hasCompatibilityReportOnly = false })
                        }
                        Button("Reset filters", systemImage: "xmark") { resetFilters() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Clear active filters")
                    }
                }
            }
        }
    }

    private func filterMenus(_ catalog: AppleGamingWikiCatalog) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                genreMenu(catalog)
                compatibilityMenu
                storefrontMenu
                if scope == .windows { windowsMethodMenu }
                filtersMenu
            }
        }
    }

    private var hasActiveFilters: Bool {
        genre != "All genres"
            || rating != "All ratings"
            || storefront != "All stores"
            || (scope == .windows && windowsMethod != .all)
            || hasCompatibilityReportOnly
    }

    private func activeFilterChip(_ title: String, reset: @escaping () -> Void) -> some View {
        Button {
            reset()
        } label: {
            HStack(spacing: 5) {
                Text(LocalizedStringKey(title))
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Remove active filter")
    }

    private func genreMenu(_ catalog: AppleGamingWikiCatalog) -> some View {
        let genres = projection.genres
        return Menu {
            filterOption("All genres", selected: genre == "All genres") { genre = "All genres" }
            ForEach(genres, id: \.self) { value in
                filterOption(value, selected: genre == value) { genre = value }
            }
            filterOption("Not provided", selected: genre == "Not provided") { genre = "Not provided" }
        } label: {
            Label(genre == "All genres" ? String(localized: "Genre") : genre, systemImage: "tag")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var compatibilityMenu: some View {
        Menu {
            filterOption("All ratings", selected: rating == "All ratings") { rating = "All ratings" }
            ForEach(AppleGamingWikiRating.allCases.filter { $0 != .notApplicable }, id: \.self) { value in
                filterOption(value.displayName, selected: rating == value.rawValue) { rating = value.rawValue }
            }
        } label: {
            Label(
                rating == "All ratings" ? String(localized: "Compatibility") : (AppleGamingWikiRating(rawValue: rating)?.displayName ?? rating),
                systemImage: "checkmark.seal")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var storefrontMenu: some View {
        Menu {
            filterOption("All stores", selected: storefront == "All stores") { storefront = "All stores" }
            filterOption("Steam", selected: storefront == "Steam") { storefront = "Steam" }
            filterOption("Other / unknown", selected: storefront == "Other / unknown") { storefront = "Other / unknown" }
        } label: {
            Label(storefront == "All stores" ? String(localized: "Store") : storefront, systemImage: "bag")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var windowsMethodMenu: some View {
        Menu {
            filterOption("All Windows paths", selected: windowsMethod == .all) { windowsMethod = .all }
            ForEach([AppleGamingWikiPlatform.crossover, .wine, .parallels], id: \.self) { value in
                filterOption(value.title, selected: windowsMethod == value) { windowsMethod = value }
            }
        } label: {
            Label(windowsMethod == .all ? String(localized: "Windows path") : windowsMethod.title, systemImage: "wineglass")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var filtersMenu: some View {
        Menu {
            Toggle("Has compatibility report", isOn: $hasCompatibilityReportOnly)
                .help("Only entries with community compatibility reports. These are not tests performed by Boreal.")
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(["Recommended", "Name A–Z", "Name Z–A"], id: \.self) { value in
                filterOption(value, selected: sortOrder == value) {
                    sortOrder = value
                }
            }
        } label: {
            Label(sortLabel, systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var sortLabel: String {
        switch sortOrder {
        case "Recommended": String(localized: "Sort: Recommended")
        case "Name A–Z": String(localized: "Sort: Name A–Z")
        case "Name Z–A": String(localized: "Sort: Name Z–A")
        default: String(localized: "Sort: Recommended")
        }
    }

    private var layoutPicker: some View {
        Picker("View", selection: $listLayout) {
            Image(systemName: "square.grid.2x2").tag(false)
            Image(systemName: "list.bullet").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 76)
        .help("Choose grid or list view")
        .accessibilityLabel("View layout")
    }

    private func filterOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
                Text(LocalizedStringKey(title))
            }
        }
    }

    private func recommended(_ games: [AppleGamingWikiGame], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Best compatibility").font(.title3.bold())
                    Text("Strongest available community compatibility reports.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(min(4, games.count)) \(String(localized: "results"))").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(games.prefix(4))) { game in
                        DiscoveryGameTile(game: game, scope: scope, windowsMethod: windowsMethod) { selectGame(game) }.frame(width: min(280, width))
                    }
                }
            }
        }
    }

    private func catalogContent(_ catalog: AppleGamingWikiCatalog, width: CGFloat) -> some View {
        let games = projection.games
        let start = min(page * pageSize, games.count)
        let end = min(start + pageSize, games.count)
        let visibleGames = Array(games[start..<end])
        let columnCount = max(1, Int((width + 16) / 256))
        let cardWidth = max(1, (width - CGFloat(columnCount - 1) * 16) / CGFloat(columnCount))
        let columns = Array(repeating: GridItem(.fixed(cardWidth), spacing: 16), count: columnCount)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(scope.title).font(.title3.bold())
                Text("\(games.count.formatted()) \(String(localized: "results"))").foregroundStyle(.secondary)
                Spacer()
            }
            if games.count > pageSize && projection.filters == projectionRequest.filters {
                pageControls(resultCount: games.count)
            }
            if projection.filters != projectionRequest.filters
                || games.isEmpty && (!query.isEmpty && store.discoverySearchState == .loading || store.discoveryState == .loading)
            {
                ProgressView("Searching…").frame(maxWidth: .infinity).padding(32)
            } else if games.isEmpty {
                ContentUnavailableView("No games found", systemImage: "magnifyingglass", description: Text("Try another search or reset your filters."))
                if hasActiveFilters || !query.isEmpty {
                    Button("Reset filters") { resetFilters() }
                }
            } else if listLayout {
                LazyVStack(spacing: 8) {
                    ForEach(visibleGames) { game in
                        DiscoveryGameTile(game: game, horizontal: width >= 480, scope: scope, windowsMethod: windowsMethod, artworkWidth: 176) {
                            selectGame(game)
                        }
                    }
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(visibleGames) { game in
                        DiscoveryGameTile(game: game, scope: scope, windowsMethod: windowsMethod) { selectGame(game) }
                            .frame(width: cardWidth)
                    }
                }
            }
            if !games.isEmpty && projection.filters == projectionRequest.filters {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Text("Showing \(start + 1)–\(end) of \(games.count.formatted()) results")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        pageControls(resultCount: games.count)
                    }
                    VStack(spacing: 12) {
                        Text("Showing \(start + 1)–\(end) of \(games.count.formatted()) results")
                            .font(.caption).foregroundStyle(.secondary)
                        pageControls(resultCount: games.count)
                    }
                }
                .padding(.vertical, 12)
            }
            loadMoreTrigger(catalog)
            Text(catalog.isStale ? "Showing the last saved catalog." : "Updated \(catalog.fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func pageControls(resultCount: Int) -> some View {
        HStack(spacing: 12) {
            Button("Previous", systemImage: "chevron.left") { page = max(0, page - 1) }
                .disabled(page == 0)
            TextField("Page", text: $pageInput)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .accessibilityLabel("Page")
                .help("Enter a page number and press Return")
                .onSubmit {
                    if let requested = Int(pageInput) {
                        page = min(max(1, requested), max(1, (resultCount + pageSize - 1) / pageSize)) - 1
                    }
                    pageInput = String(page + 1)
                }
            Text("/ \(max(1, (resultCount + pageSize - 1) / pageSize))")
                .font(.callout.monospacedDigit())
            Button("Next", systemImage: "chevron.right") { page = min(page + 1, max(0, (resultCount - 1) / pageSize)) }
                .disabled((page + 1) * pageSize >= resultCount)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func loadMoreTrigger(_ catalog: AppleGamingWikiCatalog) -> some View {
        if query.isEmpty, (catalog.steamOffset ?? 0) < (catalog.steamTotal ?? 0) {
            if store.discoveryPaginationState == .loading {
                ProgressView("Loading more games…")
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if case .failed(let message) = store.discoveryPaginationState {
                VStack(spacing: 10) {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Retry", systemImage: "arrow.clockwise") { store.loadMoreDiscoveryGames() }
                }
                .frame(maxWidth: .infinity).padding(16)
            } else {
                Button("Load more games", systemImage: "arrow.down") { store.loadMoreDiscoveryGames() }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                if let game = store.discoveryCatalog?.games.first(where: { $0.coverURL != nil }) {
                    DiscoveryArtwork(imageURL: game.coverURL, title: game.title, isLoading: false, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text("Find the best way to play").font(.title2.bold())
                Text("Discover games, compare compatibility reports and choose a setup for your Mac.").foregroundStyle(.secondary)
            }.padding(16).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            Text("Data sources").font(.headline)
            Label(
                "Compatibility reports: AppleGamingWiki. Store metadata and artwork: Steam. Price data: IsThereAnyDeal when configured.",
                systemImage: "info.circle"
            )
            .font(.callout).foregroundStyle(.secondary)
            if let notice = store.discoveryCatalog?.sourceNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            guideRow("Compatibility ratings", "Community reports for Native, Rosetta 2, CrossOver, Wine and Parallels.", "checkmark.seal")
            guideRow("Store links", "Open the game's verified store page or search another storefront.", "link")
            guideRow("Performance insights", "Read hardware and configuration reports on the source page.", "chart.bar")
            guideRow("Save for later", "Save games you’re interested in Discovery. Adding to your library is a separate action.", "bookmark")
            Text(
                "A macOS listing does not confirm Apple Silicon or current macOS compatibility. ‘Playable’ requires a Perfect or Playable community rating; reaching a menu is insufficient."
            )
            .font(.caption).foregroundStyle(.secondary)
            Link("Open compatibility documentation ↗", destination: AppleGamingWikiDiscoveryService.masterListURL)
        }
    }

    private func guideRow(_ title: String, _ description: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).frame(width: 44, height: 44).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func resetFilters() {
        genre = "All genres"
        rating = "All ratings"
        storefront = "All stores"
        windowsMethod = .all
        hasCompatibilityReportOnly = false
        sortOrder = "Recommended"
        scope = .all
        searchText = ""
    }

}

private struct DiscoveryMacProfile: Sendable {
    let chip: String
    let memory: String
    let os: String

    var summary: String { "\(chip) · \(memory) · \(os)" }

    static let current: Self = {
        let processor = hardwareString("machdep.cpu.brand_string") ?? hardwareString("hw.model") ?? "This Mac"
        let chip: String
        if processor.hasPrefix("Apple ") {
            chip = processor
        } else if processor.localizedCaseInsensitiveContains("Intel") {
            chip = "Intel Mac"
        } else {
            chip = processor == "This Mac" ? processor : "Mac"
        }
        let memoryGB = max(1, Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()))
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(version.majorVersion).\(version.minorVersion)"
        return Self(chip: chip, memory: "\(memoryGB) GB", os: os)
    }()

    private static func hardwareString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}

struct DiscoveryGameTile: View {
    @Environment(BorealStore.self) private var store
    @AppStorage(ITADPriceService.apiKeyDefaultsKey) private var itadAPIKey = ""
    @AppStorage(ITADPriceService.countryCodeDefaultsKey) private var itadCountryCode = "PL"
    let game: AppleGamingWikiGame
    var horizontal = false
    var scope: DiscoveryScope = .all
    var windowsMethod: AppleGamingWikiPlatform = .all
    var artworkWidth: CGFloat = 105
    let open: () -> Void
    @State private var isHovered = false
    private var metadata: DiscoveryGameMetadata? { store.discoveryMetadata(for: game) }

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .top, spacing: 12) {
                    artwork.frame(width: artworkWidth)
                    details.layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    artwork
                    details.padding(14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(isHovered ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(isHovered ? 0.16 : 0.08)))
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .shadow(color: .black.opacity(isHovered ? 0.18 : 0), radius: 12, y: 3)
        .onHover { isHovered = $0 }
        .task(id: "\(game.id)-\(itadAPIKey)-\(itadCountryCode)") {
            // Catalog rows already carry artwork, tags and store identity for Steam games.
            // Fetch full descriptions on the detail screen instead of for every card.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            if game.steamAppID == nil || game.genres?.isEmpty != false {
                await store.ensureDiscoveryMetadata(for: game)
            }
            guard !Task.isCancelled else { return }
            if !itadAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await store.ensureDiscoveryPrice(for: game)
            }
        }
    }

    private var artwork: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                DiscoveryArtwork(
                    imageURL: (game.steamAppID ?? metadata?.steamAppID).map {
                        "https://cdn.cloudflare.steamstatic.com/steam/apps/\($0)/header.jpg"
                    } ?? metadata?.coverImageURL ?? game.coverURL,
                    fallbackImageURL: metadata?.coverImageURL ?? game.coverURL,
                    title: game.title,
                    isLoading: store.isDiscoveryMetadataLoading(for: game),
                    height: horizontal ? 106 : 152
                )
            }
            .buttonStyle(.plain)

            Button {
                store.toggleDiscoveryGame(game)
            } label: {
                Image(systemName: store.isDiscoveryGameSaved(game) ? "bookmark.fill" : "bookmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.52), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .padding(9)
            .help(store.isDiscoveryGameSaved(game) ? "Remove from saved games" : "Save to Discovery")
            .accessibilityLabel(store.isDiscoveryGameSaved(game) ? "Saved" : "Save")
            .accessibilityAddTraits(store.isDiscoveryGameSaved(game) ? .isSelected : [])
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: horizontal ? 7 : 9) {
            Button(action: open) {
                Text(game.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text(genreDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    platformBadge
                    compatibilityBadge
                }
                VStack(alignment: .leading, spacing: 6) {
                    platformBadge
                    compatibilityBadge
                }
            }

            discoveryPrice
            HStack(spacing: 8) {
                storeReference
                Spacer(minLength: 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: horizontal ? 118 : 168, alignment: .topLeading)
    }

    private var genreDescription: String {
        let genres = game.genres?.isEmpty == false ? game.genres : metadata?.genres
        guard let genres, !genres.isEmpty else { return String(localized: "Genre not provided") }
        return genres.prefix(2).joined(separator: " · ")
    }

    @ViewBuilder private var compatibilityBadge: some View {
        if let rating = reportedRatings.min(by: { $0.rating.rank < $1.rating.rank })?.rating {
            DiscoveryRatingLabel(title: "Compatibility", rating: rating)
        } else {
            Label("No compatibility data", systemImage: "questionmark.circle")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var reportedRatings: [AppleGamingWikiRatingEntry] {
        game.availableRatings.filter { entry in
            switch scope {
            case .mac: ["Native", "Rosetta 2"].contains(entry.title)
            case .windows:
                windowsMethod == .all
                    ? ["CrossOver", "Wine", "Parallels"].contains(entry.title)
                    : entry.title.lowercased() == windowsMethod.rawValue
            case .all, .recommended: true
            }
        }
    }

    private var bestMethod: String {
        reportedRatings.filter { $0.rating.isPlayable }
            .min(by: { $0.rating.rank < $1.rating.rank })?.title ?? "Unverified"
    }

    private var platformBadge: some View {
        Label(platformTitle, systemImage: platformSymbol)
            .font(horizontal ? .caption2.weight(.semibold) : .caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private var platformTitle: String {
        if scope == .windows {
            return isWindowsPath ? "\(String(localized: "Windows")) · \(localizedBestMethod)" : String(localized: "Windows")
        }
        if isWindowsPath { return "\(String(localized: "Windows")) · \(localizedBestMethod)" }
        if bestMethod == "Native" { return String(localized: "Native macOS") }
        if bestMethod == "Rosetta 2" { return String(localized: .Compatibility.rosetta2Title) }
        if let macSupportKind = game.macSupportKind {
            if macSupportKind == .macOS, isWindowsPath {
                return "\(macSupportKind.title) · \(localizedBestMethod)"
            }
            return macSupportKind.title
        }
        return isWindowsPath ? "\(String(localized: "Windows")) · \(localizedBestMethod)" : String(localized: "Windows")
    }

    private var isWindowsPath: Bool {
        ["CrossOver", "Wine", "Parallels"].contains(bestMethod)
    }

    private var localizedBestMethod: String {
        switch bestMethod {
        case "CrossOver": String(localized: .Compatibility.crossOverTitle)
        case "Wine": String(localized: .Compatibility.wineTitle)
        case "Parallels": String(localized: .Compatibility.parallelsTitle)
        case "Rosetta 2": String(localized: .Compatibility.rosetta2Title)
        case "Native": String(localized: .Compatibility.nativeTitle)
        default: bestMethod
        }
    }

    private var platformSymbol: String {
        if bestMethod == "Native" { return "apple.logo" }
        if bestMethod == "Rosetta 2" { return "cpu" }
        if !isWindowsPath, scope != .windows, let macSupportKind = game.macSupportKind { return macSupportKind.symbol }
        switch bestMethod {
        case "CrossOver": return "rectangle.2.swap"
        case "Parallels": return "rectangle.split.3x1"
        case "Wine": return "wineglass"
        case "Rosetta 2": return "cpu"
        default: return "rectangle.on.rectangle"
        }
    }

    @ViewBuilder private var discoveryPrice: some View {
        if let offer = store.discoveryPriceSummary(for: game)?.bestOffer {
            HStack(spacing: 6) {
                Spacer(minLength: 4)
                Text(offer.price.formatted)
                    .font(horizontal ? .headline.weight(.semibold) : .callout.weight(.semibold))
                    .foregroundStyle(.primary)
                if let discount = offer.discountLabel {
                    Text(discount)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
        } else if store.isDiscoveryPriceLoading(for: game) {
            Label("Loading price…", systemImage: "arrow.triangle.2.circlepath")
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Price unavailable")
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
                .help(
                    itadAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Add an IsThereAnyDeal API key in Settings to load prices." : "No current offer was found.")
        }
    }

    @ViewBuilder private var storeReference: some View {
        let storeName = store.discoveryPriceSummary(for: game)?.bestOffer?.shop.name
        let steamID = game.steamAppID ?? metadata?.steamAppID
        if let storeName, storeName.caseInsensitiveCompare("Steam") == .orderedSame,
            let steamID,
            let url = URL(string: "https://store.steampowered.com/app/\(steamID)/")
        {
            Link(destination: url) {
                Label(storeName, systemImage: "bag")
                    .font(horizontal ? .caption : .caption2)
            }
            .help("Open Steam store page")
        } else if let storeName {
            Text(storeName)
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let steamID,
            let url = URL(string: "https://store.steampowered.com/app/\(steamID)/")
        {
            Link(destination: url) {
                Label("Steam", systemImage: "bag")
                    .font(horizontal ? .caption : .caption2)
            }
            .help("Open Steam store page")
        } else {
            Text("Store unavailable")
                .font(horizontal ? .caption : .caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct SavedDiscoveryGamesView: View {
    @Environment(BorealStore.self) private var store
    var searchText: String
    @State private var selectedGame: AppleGamingWikiGame?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved from Discovery").font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(store.savedDiscoveryGames.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }) { game in
                        DiscoveryGameTile(game: game, horizontal: true) { selectedGame = game }.frame(width: 320)
                    }
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 12)
            .sheet(item: $selectedGame) { DiscoveryGameDetailView(game: $0) }
    }
}

private struct DiscoveryArtwork: View {
    let imageURL: String?
    var fallbackImageURL: String? = nil
    let title: String
    let isLoading: Bool
    let height: CGFloat
    @State private var loadedImage: NSImage?
    @State private var attemptedLoad = false

    var body: some View {
        // Layout uses the card's proposed width, never the bitmap's intrinsic size.
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [.indigo.opacity(0.78), .cyan.opacity(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if let loadedImage {
                    Image(nsImage: loadedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: height)
                        .clipped()
                } else if imageURL != nil && !attemptedLoad {
                    placeholder.overlay { ProgressView().tint(.white) }
                } else if isLoading {
                    placeholder.overlay { ProgressView().tint(.white) }
                } else {
                    placeholder
                }
            }
            .frame(width: geometry.size.width, height: height)
            .clipped()
        }
        .frame(height: height)
        .accessibilityLabel("Cover for \(title)")
        .task(id: "\(imageURL ?? "")|\(fallbackImageURL ?? "")") {
            loadedImage = nil
            attemptedLoad = false
            for candidate in [imageURL, fallbackImageURL].compactMap({ $0 }).uniqued() {
                guard let url = URL(string: candidate) else { continue }
                if let image = await DiscoveryImagePipeline.shared.image(for: url, maxPixelSize: 560) {
                    guard !Task.isCancelled else { return }
                    loadedImage = image
                    attemptedLoad = true
                    return
                }
            }
            attemptedLoad = true
        }
    }

    private var placeholder: some View {
        VStack(spacing: 9) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 34, weight: .medium))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .foregroundStyle(.white.opacity(0.88))
    }
}

extension Sequence where Element: Hashable {
    fileprivate func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

private struct DiscoveryRatingLabel: View {
    let title: String
    let rating: AppleGamingWikiRating
    var compact = false

    var body: some View {
        Label {
            Text(compact ? "\(title): \(rating.displayName)" : rating.displayName)
                .lineLimit(1)
        } icon: {
            Image(systemName: rating.symbol)
        }
        .font(compact ? .caption2 : .callout.weight(.semibold))
        .foregroundStyle(rating.color)
    }
}

struct DiscoveryGameDetailView: View {
    @Environment(BorealStore.self) private var store
    let game: AppleGamingWikiGame
    var onSelectProducer: (String) -> Void = { _ in }
    @State private var details: StoreLibraryGame?
    @State private var finishedLoading = false
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let details {
                StoreGameDetailView(game: details, discoveryGame: game, onSelectProducer: onSelectProducer)
            } else if finishedLoading {
                ContentUnavailableView {
                    Label("Game details unavailable", systemImage: "gamecontroller")
                } description: {
                    Text("Boreal could not match \(game.title) to an unambiguous store record.")
                } actions: {
                    Button("Retry", systemImage: "arrow.clockwise") { retryCount += 1 }
                    if let url = URL(string: game.pageURL) {
                        Link("Open source page", destination: url)
                    }
                }
            } else {
                ProgressView("Loading details from Steam and compatibility sources…")
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .task(id: "\(game.id)|\(retryCount)") {
            finishedLoading = false
            details = nil
            await store.ensureDiscoveryMetadata(for: game)
            guard !Task.isCancelled else { return }
            details = await store.discoveryStoreDetails(for: game)
            if !Task.isCancelled {
                finishedLoading = true
            }
        }
    }
}

extension AppleGamingWikiRating {
    nonisolated var rank: Int { Self.allCases.firstIndex(of: self) ?? 5 }
    var color: Color {
        switch self {
        case .perfect: .green
        case .playable: .teal
        case .runs: .cyan
        case .menu: .orange
        case .unplayable: .red
        case .unknown, .notApplicable: .secondary
        }
    }
}
