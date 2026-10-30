import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    let transitionNamespace: Namespace.ID
    let selectedTransitionGameID: UUID?
    let transitionPhase: GameDetailsTransitionPhase
    let selectDiscoveryGameAction: (AppleGamingWikiGame) -> Void
    @AppStorage("developerMode") private var developerMode = false
    @State private var removeCandidate: WindowsApplication?
    @State private var uninstallCandidate: StoreLibraryGame?
    @State private var libraryRemovalCandidate: LibraryItem?
    @State private var coverEditorState: LibraryCoverEditorState?
    @State private var pendingFavoriteRemovals: Set<String> = []
    @State private var projectedLibrary = LibraryProjectionCache()

    private var motion: BorealMotionEnvironment {
        BorealMotionEnvironment(reduceMotion: reduceMotion)
    }

    private var allItems: [LibraryItem] {
        projectedLibrary.items(
            applications: store.applications,
            storeGames: store.storeGames,
            installations: store.installations,
            hiddenKeys: store.hiddenLibraryKeys
        )
    }

    private var items: [LibraryItem] {
        LibraryProjector.project(
            allItems, searchText: searchText,
            sources: rawSet(sourceFilters, as: LibrarySourceFilter.self),
            availability: rawSet(availabilityFilters, as: LibraryAvailabilityFilter.self),
            compatibility: rawSet(compatibilityFilters, as: LibraryCompatibilityFilter.self),
            sort: sort, producer: producerFilter,
            favorites: favoritesOnly ? store.favoriteKeys.union(pendingFavoriteRemovals) : [], favoritesOnly: favoritesOnly
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
            Text(.Library.removeFromLibraryTitle(libraryRemovalCandidate?.name ?? "game")),
            isPresented: Binding(get: { libraryRemovalCandidate != nil }, set: { if !$0 { libraryRemovalCandidate = nil } })
        ) {
            Button(.Library.removeFromLibrary, role: .destructive) {
                if let item = libraryRemovalCandidate { store.removeFromLibrary(key: item.favoriteKey) }
                libraryRemovalCandidate = nil
            }
            Button(.Library.cancel, role: .cancel) { libraryRemovalCandidate = nil }
        } message: {
            Text(.Library.removeFromLibraryMessage)
        }
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
        .sheet(item: $coverEditorState) { state in
            CustomCoverEditorView(
                title: state.item.name,
                sourceLabel: String(localized: state.item.source.title),
                statusLabel: String(localized: state.item.localizedStatusText),
                sourceData: state.sourceData,
                initialCrop: state.crop,
                onCancel: { coverEditorState = nil },
                onSave: { originalData, renderedData, crop in
                    switch state.item.kind {
                    case .application(let application):
                        store.saveCustomArtwork(
                            originalData: originalData,
                            renderedData: renderedData,
                            crop: crop,
                            for: application.id
                        )
                    case .storeGame(let game):
                        store.saveCustomArtwork(
                            originalData: originalData,
                            renderedData: renderedData,
                            crop: crop,
                            forStoreGameID: game.id
                        )
                    }
                    coverEditorState = nil
                }
            )
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
            .animation(motion.panel, value: pendingFavoriteRemovals)
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
            Button { select(item) } label: {
                featuredArtwork(item)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(item.name))
            LinearGradient(
                colors: [.clear, .black.opacity(0.32), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
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
            if let image = ArtworkImageCache.customImage(
                processedPath: app.customArtworkPath,
                originalPath: app.customArtworkOriginalPath
            ) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.indigo.opacity(0.9), .cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay { Image(systemName: app.iconSymbol).font(.system(size: 92)).foregroundStyle(.white.opacity(0.22)) }
            }
        case .storeGame(let game):
            GeometryReader { geometry in
                GameArtworkView(
                    game: game,
                    width: geometry.size.width,
                    height: geometry.size.height,
                    usesCustomArtwork: false,
                    kind: .hero,
                    displayMode: .fill,
                    showsChrome: false
                )
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
            gridItemCard(item, hovering: transitionPhase == .library && hovering)
        }
        .zIndex(isSelectedTransitionItem(item) ? 100 : 0)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func gridItemCard(_ item: LibraryItem, hovering: Bool) -> some View {
        let contextMenu = erasedItemContextMenu(item)
        return AnyView(
            ZStack {
                Button { select(item) } label: {
                    transitionableLibraryArtwork(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LibraryArtworkButtonStyle())
                    .onDrop(
                        of: [UTType.image.identifier, UTType.fileURL.identifier],
                        isTargeted: nil,
                        perform: { providers in
                            handleArtworkDrop(providers, for: item)
                        }
                    )

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.28),
                        .init(color: .black.opacity(0.32), location: 0.52),
                        .init(color: .black.opacity(0.94), location: 0.76)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Label(
                            item.localizedCompatibilityText,
                            systemImage: item.supportsNativeMacOS ? "apple.logo" : item.compatibility.symbol
                        )
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(compatibilityColor(item))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.58), in: Capsule())
                        Spacer(minLength: 8)
                        favoriteButton(for: item, isHovered: hovering)
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
                                    item.readyToPlay ? .Library.installed : (item.status == .available ? .Library.notInstalled : item.localizedStatusText),
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
                                .buttonStyle(LibraryPressButtonStyle())
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                            Menu {
                                erasedItemContextMenu(item)
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
        )
        .modifier(
            LibraryCardPresentationModifier(
                hovering: hovering,
                cornerRadius: isSelectedTransitionItem(item) ? 20 : 15,
                contextMenu: contextMenu,
                accessibilityText: "\(item.name), \(item.source.title), \(item.localizedCompatibilityText), \(item.localizedStatusText)",
                reduceMotion: reduceMotion
            )
        )
    }

    @ViewBuilder private func libraryCardArtwork(_ item: LibraryItem) -> some View {
        switch item.kind {
        case .application(let app):
            if let image = ArtworkImageCache.customImage(
                processedPath: app.customArtworkPath,
                originalPath: app.customArtworkOriginalPath
            ) {
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
                    height: geometry.size.height,
                    cornerRadius: isSelectedTransitionItem(item) ? 20 : 16
                )
            }
        }
    }

    @ViewBuilder private func transitionableLibraryArtwork(_ item: LibraryItem) -> some View {
        if case .storeGame(let game) = item.kind,
           (transitionPhase == .opening || transitionPhase == .closing) {
            libraryCardArtwork(item)
                .matchedGeometryEffect(
                    id: game.id,
                    in: transitionNamespace,
                    isSource: transitionPhase != .closing
                )
        } else {
            libraryCardArtwork(item)
        }
    }

    private func isSelectedTransitionItem(_ item: LibraryItem) -> Bool {
        guard case .storeGame(let game) = item.kind else { return false }
        return selectedTransitionGameID == game.id
    }

    private func favoriteButton(for item: LibraryItem, isHovered: Bool) -> some View {
        let favorite = store.isFavorite(key: item.favoriteKey)
        return FavoriteButton(
            isFavorite: favorite,
            isHovered: isHovered,
            revealsOnHover: true,
            helpText: String(localized: favorite ? .Library.removeFromFavorites : .Library.addToFavorites),
            accessibilityText: String(localized: favorite ? .Library.removeItemFromFavorites(item.name) : .Library.addItemToFavorites(item.name))
        ) {
            toggleFavorite(item, wasFavorite: favorite)
        }
    }

    private func toggleFavorite(_ item: LibraryItem, wasFavorite: Bool) {
        let key = item.favoriteKey
        withAnimation(motion.control) {
            store.toggleFavorite(key: key)
            if favoritesOnly, wasFavorite {
                pendingFavoriteRemovals.insert(key)
            } else {
                pendingFavoriteRemovals.remove(key)
            }
        }

        guard favoritesOnly, wasFavorite else { return }
        let removalDelay = reduceMotion ? 0.08 : 0.18
        DispatchQueue.main.asyncAfter(deadline: .now() + removalDelay) {
            guard pendingFavoriteRemovals.contains(key) else { return }
            withAnimation(motion.panel) {
                pendingFavoriteRemovals.remove(key)
            }
        }
    }

    @ViewBuilder private func itemIcon(_ item: LibraryItem, compact: Bool) -> some View {
        switch item.kind {
        case .application(let app):
            AppIconView(symbol: app.iconSymbol, size: compact ? 32 : 92)
        case .storeGame(let game):
            GameArtworkView(
                game: game,
                width: compact ? 32 : 148,
                height: compact ? 48 : 222,
                usesCustomArtwork: false
            )
        }
    }

    @ViewBuilder private func itemContextMenu(_ item: LibraryItem) -> some View {
        switch item.kind {
        case .application(let app):
            appContextMenu(app)
            Divider()
            customArtworkMenu(for: item)
            Divider()
            Button(.Library.removeFromLibrary, systemImage: "rectangle.badge.minus", role: .destructive) {
                libraryRemovalCandidate = item
            }
        case .storeGame:
            if item.readyToPlay || item.running {
                Button(quickActionTitle(item), systemImage: quickActionSymbol(item)) { quickAction(item) }
                Divider()
            }
            Button(.Library.showDetails, systemImage: "info.circle") { select(item) }
            Divider()
            customArtworkMenu(for: item)
            Divider()
            Button(.Library.removeFromLibrary, systemImage: "rectangle.badge.minus", role: .destructive) {
                libraryRemovalCandidate = item
            }
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

    private func erasedItemContextMenu(_ item: LibraryItem) -> AnyView {
        AnyView(itemContextMenu(item))
    }

    private struct LibraryCardContextMenuModifier: ViewModifier {
        let menu: AnyView

        func body(content: Content) -> some View {
            content.contextMenu {
                menu
            }
        }
    }

    private struct LibraryArtworkButtonStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .opacity(configuration.isPressed ? 0.86 : 1)
                .animation(BorealMotionEnvironment(reduceMotion: reduceMotion).instant, value: configuration.isPressed)
        }
    }

    private struct LibraryPressButtonStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(configuration.isPressed ? 0.88 : 1)
                .animation(BorealMotionEnvironment(reduceMotion: reduceMotion).instant, value: configuration.isPressed)
        }
    }

    private struct LibraryCardPresentationModifier: ViewModifier {
        let hovering: Bool
        let cornerRadius: CGFloat
        let contextMenu: AnyView
        let accessibilityText: String
        let reduceMotion: Bool

        func body(content: Content) -> some View {
            let shaped = content
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            let outlined = shaped.overlay(LibraryCardOutline(hovering: hovering, cornerRadius: cornerRadius))

            return outlined
                .shadow(
                    color: hovering ? Color.accentColor.opacity(0.24) : .black.opacity(0.24),
                    radius: hovering ? 14 : 9,
                    y: 5
                )
                .scaleEffect(hovering ? 1.012 : 1)
                .animation(BorealMotionEnvironment(reduceMotion: reduceMotion).hover, value: hovering)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .modifier(LibraryCardContextMenuModifier(menu: contextMenu))
                .accessibilityLabel(Text(accessibilityText))
        }
    }

    private struct LibraryCardOutline: View {
        let hovering: Bool
        let cornerRadius: CGFloat

        var body: some View {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    hovering ? Color.accentColor : Color.white.opacity(0.15),
                    lineWidth: hovering ? 3 : 1
                )
        }
    }

    @ViewBuilder private func customArtworkMenu(for item: LibraryItem) -> some View {
        Button(itemHasCustomArtwork(item) ? "Edit Cover…" : "Change Cover…", systemImage: "photo.on.rectangle") {
            chooseCustomArtwork(for: item)
        }
        if itemHasCustomArtwork(item) {
            Button("Reset to Default", systemImage: "arrow.uturn.backward") {
                resetCustomArtwork(for: item)
            }
        }
    }

    private func itemHasCustomArtwork(_ item: LibraryItem) -> Bool {
        switch item.kind {
        case .application(let application):
            application.customArtworkPath != nil || application.customArtworkOriginalPath != nil
        case .storeGame(let game):
            game.customArtworkPath != nil || game.customArtworkOriginalPath != nil
        }
    }

    private func chooseCustomArtwork(for item: LibraryItem) {
        if let existing = customArtworkSource(for: item) {
            presentCoverEditor(for: item, sourceData: existing.data, crop: existing.crop)
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Change Cover"
        panel.message = "Select an image to crop for this game's cover."
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: sourceURL), NSImage(data: data) != nil else { return }
        presentCoverEditor(for: item, sourceData: data, crop: .centered)
    }

    private func customArtworkSource(for item: LibraryItem) -> (data: Data, crop: ArtworkCrop)? {
        let originalPath: String?
        let processedPath: String?
        let crop: ArtworkCrop?
        switch item.kind {
        case .application(let application):
            originalPath = application.customArtworkOriginalPath
            processedPath = application.customArtworkPath
            crop = application.customArtworkCrop
        case .storeGame(let game):
            originalPath = game.customArtworkOriginalPath
            processedPath = game.customArtworkPath
            crop = game.customArtworkCrop
        }
        if let originalPath, let data = try? Data(contentsOf: URL(fileURLWithPath: originalPath)), NSImage(data: data) != nil {
            return (data, crop ?? .centered)
        }
        if let processedPath, let data = try? Data(contentsOf: URL(fileURLWithPath: processedPath)), NSImage(data: data) != nil {
            return (data, .centered)
        }
        return nil
    }

    private func presentCoverEditor(for item: LibraryItem, sourceData: Data, crop: ArtworkCrop) {
        guard NSImage(data: sourceData) != nil else { return }
        coverEditorState = LibraryCoverEditorState(item: item, sourceData: sourceData, crop: crop)
    }

    private func handleArtworkDrop(_ providers: [NSItemProvider], for item: LibraryItem) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            if let data, NSImage(data: data) != nil {
                DispatchQueue.main.async {
                    presentCoverEditor(for: item, sourceData: data, crop: .centered)
                }
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { fileData, _ in
                guard let fileData,
                      let url = URL(dataRepresentation: fileData, relativeTo: nil)
                        ?? String(data: fileData, encoding: .utf8).flatMap(URL.init(string:)),
                      let imageData = try? Data(contentsOf: url),
                      NSImage(data: imageData) != nil else { return }
                DispatchQueue.main.async {
                    presentCoverEditor(for: item, sourceData: imageData, crop: .centered)
                }
            }
        }
        return true
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
            if game.provider == .steam, store.usesSteamOnM1Wine, store.isInstalled(game),
               store.linkedApplication(for: game)?.status != .running,
               let url = URL(string: "steam://rungameid/\(game.externalID)") {
                store.openSteam(url, launchArguments: store.linkedApplication(for: game)?.resolvedCompatibilityProfile.parsedLaunchArguments ?? [])
            } else if let app = store.linkedApplication(for: game) {
                if app.status == .needsAttention || app.status == .unavailable || app.status.isBusy {
                    selectStoreGameAction(game.id)
                } else {
                    store.toggleRunning(app.id)
                }
            } else if game.provider == .steam, store.isInstalled(game),
                      let url = URL(string: "steam://rungameid/\(game.externalID)") {
                if !store.openSteam(url) {
                    // A Steam catalog entry can exist without a registered
                    // Steam URL handler. Keep the action useful by opening the
                    // game details instead of silently doing nothing.
                    selectStoreGameAction(game.id)
                }
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

    private func compatibilityColor(_ item: LibraryItem) -> Color {
        if item.supportsNativeMacOS { return .mint }
        switch item.compatibility {
        case .excellent: return .green
        case .good: return .teal
        case .limited: return .orange
        case .unsupported: return .red
        case .unknown: return .white.opacity(0.72)
        }
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

private struct LibraryCoverEditorState: Identifiable {
    let item: LibraryItem
    let sourceData: Data
    let crop: ArtworkCrop

    var id: String {
        switch item.id {
        case .application(let id): "application-cover-\(id.uuidString)"
        case .storeGame(let id): "store-game-cover-\(id.uuidString)"
        }
    }
}

struct CustomCoverEditorView: View {
    let title: String
    let sourceLabel: String
    let statusLabel: String
    let onCancel: () -> Void
    let onSave: (Data, Data, ArtworkCrop) -> Void

    @State private var sourceData: Data
    @State private var sourceImage: NSImage?
    @State private var crop: ArtworkCrop
    @State private var dragStartCrop: ArtworkCrop?
    @State private var zoomStart: Double?

    init(
        title: String,
        sourceLabel: String,
        statusLabel: String,
        sourceData: Data,
        initialCrop: ArtworkCrop,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Data, Data, ArtworkCrop) -> Void
    ) {
        self.title = title
        self.sourceLabel = sourceLabel
        self.statusLabel = statusLabel
        self.onCancel = onCancel
        self.onSave = onSave
        _sourceData = State(initialValue: sourceData)
        _sourceImage = State(initialValue: NSImage(data: sourceData))
        _crop = State(initialValue: initialCrop)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Change Cover").font(.title2.weight(.semibold))
                    Text(title).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Crop preview").font(.headline)
                    cropCanvas
                    HStack {
                        Text("Zoom").font(.caption.weight(.semibold))
                        Slider(value: $crop.scale, in: 1...3)
                            .frame(width: 180)
                        Text("\(crop.scale, format: .number.precision(.fractionLength(1)))×")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button("Reset Crop", systemImage: "arrow.counterclockwise") {
                        crop = .centered
                    }
                    .buttonStyle(.borderless)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Library preview").font(.headline)
                    cardPreview
                    Text("The preview uses the same 2:3 cover ratio as the library card.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button("Choose Image…", systemImage: "photo.on.rectangle") {
                    chooseReplacementImage()
                }
                Button("Paste Image", systemImage: "clipboard") {
                    pasteImage()
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sourceImage == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 560)
        .onPasteCommand(of: [UTType.image]) { _ in
            pasteImage()
        }
    }

    private var cropCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let sourceImage {
                    Image(nsImage: sourceImage)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(crop.scale)
                        .offset(
                            x: crop.offsetX * geometry.size.width * 0.5,
                            y: crop.offsetY * geometry.size.height * 0.5
                        )
                } else {
                    ContentUnavailableView("Image unavailable", systemImage: "photo")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(zoomGesture)
        }
        .frame(width: 280, height: 420)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartCrop == nil { dragStartCrop = crop }
                guard let start = dragStartCrop else { return }
                let nextX = start.offsetX + value.translation.width / 140
                let nextY = start.offsetY + value.translation.height / 210
                crop.offsetX = min(1, max(-1, nextX))
                crop.offsetY = min(1, max(-1, nextY))
            }
            .onEnded { _ in
                dragStartCrop = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = crop.scale }
                crop.scale = min(3, max(1, (zoomStart ?? 1) * value))
            }
            .onEnded { _ in
                zoomStart = nil
            }
    }

    private var cardPreview: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = croppedImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [.indigo, .cyan.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline.weight(.bold)).lineLimit(1)
                Text(sourceLabel).font(.caption).foregroundStyle(.white.opacity(0.8))
                Text(statusLabel).font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .frame(width: 220, height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.2)) }
    }

    private func chooseReplacementImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose Image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
        sourceData = data
        sourceImage = image
        crop = .centered
    }

    private func pasteImage() {
        guard let image = NSImage(pasteboard: NSPasteboard.general), let data = image.tiffRepresentation else { return }
        sourceData = data
        sourceImage = image
        crop = .centered
    }

    private func save() {
        guard let renderedData = renderedImageData() else { return }
        onSave(sourceData, renderedData, crop)
    }

    private func croppedImage() -> NSImage? {
        guard let sourceImage,
              let sourceCGImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sourceWidth = CGFloat(sourceCGImage.width)
        let sourceHeight = CGFloat(sourceCGImage.height)
        let targetAspect: CGFloat = 2 / 3
        let baseWidth = min(sourceWidth, sourceHeight * targetAspect)
        let baseHeight = baseWidth / targetAspect
        let cropWidth = baseWidth / min(3, max(1, crop.scale))
        let cropHeight = baseHeight / min(3, max(1, crop.scale))
        let availableX = max(0, sourceWidth - cropWidth)
        let availableY = max(0, sourceHeight - cropHeight)
        let originX = (availableX / 2) - crop.offsetX * (availableX / 2)
        let originY = (availableY / 2) - crop.offsetY * (availableY / 2)
        let imageBounds = CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
        let rect = CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
            .integral
            .intersection(imageBounds)
        guard rect.width > 0, rect.height > 0 else { return nil }
        guard let cropped = sourceCGImage.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: 600, height: 900))
    }

    private func renderedImageData() -> Data? {
        guard let image = croppedImage(),
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: 600,
                  pixelsHigh: 900,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bitmapFormat: [],
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: 600, height: 900),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
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

private struct LibraryGridHoverContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(hovering)
            .onHover { value in
                guard value != hovering else { return }
                withAnimation(BorealMotionEnvironment(reduceMotion: reduceMotion).hover) { hovering = value }
            }
    }
}

private func rawSet<Value>(_ raw: String, as type: Value.Type) -> Set<Value> where Value: RawRepresentable & Hashable, Value.RawValue == String {
    Set(raw.split(separator: ",").compactMap { Value(rawValue: String($0)) })
}

private func serialized<Value>(_ values: Set<Value>) -> String where Value: RawRepresentable, Value.RawValue == String {
    values.map(\.rawValue).sorted().joined(separator: ",")
}
