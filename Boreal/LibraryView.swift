import AppKit
import SwiftUI

nonisolated enum LibrarySort: String, CaseIterable, Sendable {
    case nameAscending, nameDescending, lastUsed, playtime, compatibility, installedFirst

    var title: String {
        switch self {
        case .nameAscending: "Name A–Z"
        case .nameDescending: "Name Z–A"
        case .lastUsed: "Last Used"
        case .playtime: "Playtime"
        case .compatibility: "Compatibility"
        case .installedFirst: "Installed First"
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

    var title: String {
        switch self {
        case .source: "Source"
        case .availability: "Availability"
        case .compatibility: "Compatibility"
        case .none: "None"
        }
    }
}

nonisolated enum LibrarySourceFilter: String, CaseIterable, Sendable {
    case boreal, steam, epic, gog

    var title: String {
        switch self {
        case .boreal: "Windows Apps"
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

    var title: String {
        switch self {
        case .installed: "Installed"
        case .notInstalled: "Not Installed"
        case .readyToPlay: "Ready to Play"
        case .recent: "Recently Used"
        case .neverUsed: "Never Used"
        case .needsAttention: "Needs Attention"
        }
    }
}

nonisolated enum LibraryCompatibilityFilter: String, CaseIterable, Sendable {
    case excellent, good, limited, unsupported, unknown
    var title: String { rawValue.capitalized }
}

nonisolated struct LibraryItem: Identifiable, Hashable, Sendable {
    nonisolated enum ID: Hashable, Sendable { case application(UUID), storeGame(UUID) }
    nonisolated enum Kind: Hashable, Sendable { case application(WindowsApplication), storeGame(StoreLibraryGame) }

    let id: ID
    let kind: Kind
    let name: String
    let subtitle: String
    let source: LibrarySourceFilter
    let installed: Bool
    let readyToPlay: Bool
    let running: Bool
    let needsAttention: Bool
    let lastUsed: Date?
    let playtimeMinutes: Int?
    let storageBytes: Int64?
    let storageIsEstimate: Bool
    let compatibility: CompatibilityRating
    let statusText: String

    var searchText: String {
        [name, subtitle, source.title, installed ? "installed" : "not installed", readyToPlay ? "ready to play" : "", needsAttention ? "needs attention" : "", compatibility.rawValue, statusText]
            .joined(separator: " ")
    }
}

nonisolated enum LibraryProjector {
    static func makeItems(applications: [WindowsApplication], storeGames: [StoreLibraryGame]) -> [LibraryItem] {
        let apps = applications.map { app in
            LibraryItem(
                id: .application(app.id), kind: .application(app), name: app.name, subtitle: app.publisher,
                source: app.storeProvider.map(source) ?? .boreal,
                installed: app.status != .unavailable,
                readyToPlay: app.status == .ready || app.status == .running,
                running: app.status == .running,
                needsAttention: app.status == .needsAttention || app.status == .unavailable,
                lastUsed: app.lastOpened, playtimeMinutes: nil, storageBytes: app.storageBytes > 0 ? app.storageBytes : nil,
                storageIsEstimate: false,
                compatibility: app.compatibility,
                statusText: app.status.rawValue
            )
        }
        let linked = Dictionary(
            applications.compactMap { app -> (String, WindowsApplication)? in
                guard let provider = app.storeProvider, let externalID = app.storeExternalID else { return nil }
                return ("\(provider.rawValue)|\(externalID)", app)
            },
            uniquingKeysWith: { first, _ in first }
        )
        // An installed store game is also represented by a WindowsApplication.
        // Keep the application entry as the canonical library item so the same
        // game is not shown once as an app and once as its store metadata.
        let games = storeGames.filter { game in
            linked["\(game.provider.rawValue)|\(game.externalID)"] == nil
        }.map { game in
            let ready = game.provider == .steam && game.isInstalled
            let running = false
            let attention = false
            return LibraryItem(
                id: .storeGame(game.id), kind: .storeGame(game), name: game.name,
                subtitle: game.developer ?? game.provider.rawValue, source: source(game.provider),
                installed: game.isInstalled, readyToPlay: ready, running: running, needsAttention: attention,
                lastUsed: game.lastPlayed, playtimeMinutes: game.playtimeMinutes,
                storageBytes: game.displayedStorageBytes,
                storageIsEstimate: game.storageBytes == nil && game.sizeEstimate?.installedBytes != nil,
                compatibility: game.compatibility?.tier.rating ?? .unknown,
                statusText: attention ? "Needs Attention" : (running ? "Running" : (ready ? "Ready" : (game.isInstalled ? "Installed" : "Available")))
            )
        }
        return apps + games
    }

    static func project(
        _ items: [LibraryItem], searchText: String, sources: Set<LibrarySourceFilter>,
        availability: Set<LibraryAvailabilityFilter>, compatibility: Set<LibraryCompatibilityFilter>,
        sort: LibrarySort
    ) -> [LibraryItem] {
        let terms = normalized(searchText).split(separator: " ").map(String.init)
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return items.filter { item in
            let haystack = normalized(item.searchText)
            guard terms.allSatisfy(haystack.contains) else { return false }
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
            guard compatibility.isEmpty || compatibility.contains(compatibilityFilter(item.compatibility)) else { return false }
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
            Menu("Sort by: \(sort.title)", systemImage: "arrow.up.arrow.down") {
                ForEach(LibrarySort.allCases, id: \.self) { value in
                    Button { sort = value } label: {
                        Label(value.title, systemImage: sort == value ? "checkmark" : value.symbol)
                    }
                }
            }
            Menu("Group by: \(grouping.title)", systemImage: "rectangle.3.group") {
                ForEach(LibraryGrouping.allCases, id: \.self) { value in
                    Button { grouping = value } label: {
                        Label(value.title, systemImage: grouping == value ? "checkmark" : "rectangle.3.group")
                    }
                }
            }
            Divider()
            Section("Source") {
                ForEach(LibrarySourceFilter.allCases, id: \.self) { filterButton($0, title: $0.title, raw: $sourceFilters) }
            }
            Section("Availability") {
                ForEach(LibraryAvailabilityFilter.allCases, id: \.self) { filterButton($0, title: $0.title, raw: $availabilityFilters) }
            }
            Section("Compatibility") {
                ForEach(LibraryCompatibilityFilter.allCases, id: \.self) { filterButton($0, title: $0.title, raw: $compatibilityFilters) }
            }
            if filterCount > 0 {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") { clearFilters() }
            }
        } label: {
            Label(filterCount == 0 ? "View Options" : "View Options \(filterCount)", systemImage: "slider.horizontal.3")
        }
        .help("Sort, group, and filter the Library")

        Picker("View", selection: $style) {
            Label("Grid", systemImage: "square.grid.2x2").tag(ContentView.LibraryStyle.grid)
            Label("List", systemImage: "list.bullet").tag(ContentView.LibraryStyle.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 86)
    }

    @ViewBuilder private func filterButton<Value>(_ value: Value, title: String, raw: Binding<String>) -> some View where Value: RawRepresentable & Hashable, Value.RawValue == String {
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
    let installAction: () -> Void
    let syncSteamAction: () -> Void
    let importAction: (URL) -> Void
    let selectAction: (UUID) -> Void
    let selectStoreGameAction: (UUID) -> Void
    @AppStorage("developerMode") private var developerMode = false
    @State private var removeCandidate: WindowsApplication?
    @State private var hoveredItemID: LibraryItem.ID?

    private var allItems: [LibraryItem] {
        LibraryProjector.makeItems(applications: store.applications, storeGames: store.storeGames)
    }

    private var items: [LibraryItem] {
        LibraryProjector.project(
            allItems, searchText: searchText,
            sources: rawSet(sourceFilters, as: LibrarySourceFilter.self),
            availability: rawSet(availabilityFilters, as: LibraryAvailabilityFilter.self),
            compatibility: rawSet(compatibilityFilters, as: LibraryCompatibilityFilter.self), sort: sort
        )
    }

    private var activeFilters: [ActiveLibraryFilter] {
        rawSet(availabilityFilters, as: LibraryAvailabilityFilter.self).map { value in
            ActiveLibraryFilter(id: "availability:\(value.rawValue)", title: value.title) { toggle(value, raw: $availabilityFilters) }
        } + rawSet(compatibilityFilters, as: LibraryCompatibilityFilter.self).map { value in
            ActiveLibraryFilter(id: "compatibility:\(value.rawValue)", title: value.title) { toggle(value, raw: $compatibilityFilters) }
        }
    }

    private var selectedSources: Set<LibrarySourceFilter> {
        rawSet(sourceFilters, as: LibrarySourceFilter.self)
    }

    private var hasActiveRefinement: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedSources.isEmpty
            || !activeFilters.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !allItems.isEmpty { sourceQuickPicker }
            if !activeFilters.isEmpty { activeFilterBar }
            Group {
                if allItems.isEmpty {
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
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, ["exe", "msi"].contains(url.pathExtension.lowercased()) else { return false }
            importAction(url)
            return true
        }
        .confirmationDialog(
            "Remove \(removeCandidate?.name ?? "application")?",
            isPresented: Binding(get: { removeCandidate != nil }, set: { if !$0 { removeCandidate = nil } })
        ) {
            Button("Remove App and Environment", role: .destructive) {
                if let id = removeCandidate?.id { store.removeApplication(id) }
                removeCandidate = nil
            }
            Button("Cancel", role: .cancel) { removeCandidate = nil }
        } message: { Text("This removes the app from Boreal. The original setup file is not deleted.") }
    }

    private var sourceQuickPicker: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    sourceButton(
                        title: "All",
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
            Divider()
        }
    }

    private func sourceButton(
        title: String,
        symbol: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
        .help(count == 0 ? "No items from \(title)" : "Show \(title) items")
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectQuickSource(_ source: LibrarySourceFilter) {
        sourceFilters = selectedSources == [source] ? "" : serialized(Set([source]))
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
                        .help("Remove \(filter.title) filter")
                    }
                    if activeFilters.count > 1 {
                        Button("Clear All") { clearFilters() }.font(.caption).buttonStyle(.plain)
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
            Label("No Matching Items", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(searchText.isEmpty ? "No items match the selected filters." : "No items match “\(searchText)” and the selected filters.")
        } actions: {
            Button("Clear Search and Filters") { searchText = ""; clearFilters() }
                .buttonStyle(.borderedProminent)
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
                                Text("\(group.items.count.formatted()) apps").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if grouping == .source, let source = group.source { syncButton(for: source) }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 170), spacing: 24)], spacing: 26) {
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
        Table(items) {
            TableColumn("Name") { item in
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
            }
            .width(min: 220, ideal: 300)
            TableColumn("Source") { item in
                Label(item.source.title, systemImage: item.source.symbol).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
            TableColumn("Status") { item in
                Label(item.statusText, systemImage: statusSymbol(item)).foregroundStyle(statusColor(item))
            }
            .width(min: 105, ideal: 135)
            TableColumn("Compatibility") { item in CompatibilityLabel(rating: item.compatibility) }
                .width(min: 115, ideal: 145)
            TableColumn("Last Used") { item in
                Text(item.lastUsed?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
                    .foregroundStyle(item.lastUsed == nil ? .secondary : .primary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Playtime") { item in
                Text(playtime(item.playtimeMinutes)).foregroundStyle(item.playtimeMinutes == nil ? .tertiary : .secondary)
            }
            .width(min: 70, ideal: 85)
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
                ("Needs Attention", { (item: LibraryItem) in item.needsAttention }),
                ("Ready to Play", { (item: LibraryItem) in !item.needsAttention && item.readyToPlay }),
                ("Installed", { (item: LibraryItem) in !item.needsAttention && !item.readyToPlay && item.installed }),
                ("Available", { (item: LibraryItem) in !item.installed })
            ].compactMap { title, matches in
                let values = items.filter(matches)
                return values.isEmpty ? nil : LibraryGroup(id: title, title: title, source: nil, items: values)
            }
        case .compatibility:
            LibraryCompatibilityFilter.allCases.compactMap { value in
                let values = items.filter { LibraryProjector.compatibilityFilter($0.compatibility) == value }
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
            Label("Needs Attention", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(spacing: 0) {
                ForEach(Array(attentionItems.enumerated()), id: \.element.id) { index, item in
                    Button { select(item) } label: {
                        HStack(spacing: 12) {
                            itemIcon(item, compact: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).fontWeight(.medium)
                                Text(item.statusText).font(.caption).foregroundStyle(.secondary)
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
                Text("Jump Back In").font(.title2.weight(.bold))
                Text("Your most recent games").font(.callout).foregroundStyle(.secondary)
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
                    Label("CONTINUE PLAYING", systemImage: "clock.arrow.circlepath")
                        .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.white.opacity(0.78))
                    Text(item.name).font(.title2.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                    Text(featuredMetadata(item)).font(.callout).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
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
        .accessibilityLabel("Continue \(item.name), \(item.statusText)")
    }

    private func recentRow(_ item: LibraryItem) -> some View {
        Button { select(item) } label: {
            HStack(spacing: 11) {
                itemIcon(item, compact: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.callout.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: item.source.symbol)
                        Text(relativeDate(item.lastUsed))
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
            LinearGradient(colors: [.indigo.opacity(0.9), .cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { Image(systemName: app.iconSymbol).font(.system(size: 92)).foregroundStyle(.white.opacity(0.22)) }
        case .storeGame(let game):
            if let path = game.artworkPath, let image = NSImage(contentsOfFile: path) {
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

    private func featuredMetadata(_ item: LibraryItem) -> String {
        [item.source.title, playtime(item.playtimeMinutes), item.statusText]
            .filter { $0 != "—" }.joined(separator: "  •  ")
    }

    private func relativeDate(_ date: Date?) -> String {
        guard let date else { return "Not played yet" }
        return date.formatted(.relative(presentation: .named))
    }

    private func showsHeader(for group: LibraryGroup) -> Bool {
        grouping != .none && !(grouping == .source && groups.count == 1)
    }

    private func gridItem(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottom) {
                Button { select(item) } label: { itemIcon(item, compact: false) }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topLeading) {
                        if item.compatibility != .unknown {
                            MacCompatibilityBadge(rating: item.compatibility, compact: true)
                                .padding(8)
                        }
                    }
                if hoveredItemID == item.id {
                    HStack(spacing: 8) {
                        Button(quickActionTitle(item), systemImage: quickActionSymbol(item)) { quickAction(item) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Menu {
                            itemContextMenu(item)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            Button { select(item) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline).lineLimit(1)
                    Label(item.statusText, systemImage: statusSymbol(item))
                        .font(.caption).foregroundStyle(statusColor(item)).lineLimit(1)
                    if let storageBytes = item.storageBytes, storageBytes > 0 {
                        Label(
                            "\(item.storageIsEstimate ? "≈ " : "")\(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))",
                            systemImage: "internaldrive"
                        )
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(7)
        .background {
            if hoveredItemID == item.id {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { hoveredItemID = hovering ? item.id : nil }
        }
        .contextMenu { itemContextMenu(item) }
        .accessibilityLabel("\(item.name), \(item.source.title), \(item.statusText)")
        .task(id: item.id) {
            if case .storeGame(let game) = item.kind {
                await store.loadStoreGameSizeIfNeeded(for: game.id)
            }
        }
    }

    @ViewBuilder private func itemIcon(_ item: LibraryItem, compact: Bool) -> some View {
        switch item.kind {
        case .application(let app): AppIconView(symbol: app.iconSymbol, size: compact ? 32 : 92)
        case .storeGame(let game): GameArtworkView(game: game, width: compact ? 32 : 148, height: compact ? 42 : 207)
        }
    }

    @ViewBuilder private func itemContextMenu(_ item: LibraryItem) -> some View {
        switch item.kind {
        case .application(let app): appContextMenu(app)
        case .storeGame:
            if item.readyToPlay || item.running {
                Button(quickActionTitle(item), systemImage: quickActionSymbol(item)) { quickAction(item) }
                Divider()
            }
            Button("Show Details", systemImage: "info.circle") { select(item) }
        }
    }

    @ViewBuilder private func syncButton(for source: LibrarySourceFilter) -> some View {
        if let provider = provider(source) {
            if libraryIsSyncing(provider) {
                ProgressView().controlSize(.small).help("Importing \(provider.rawValue) Library")
            } else {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    store.syncLibrary(provider)
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("Refresh \(provider.rawValue) Library")
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
        if case .syncing(let active) = store.librarySyncState { return active == provider }
        return false
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
            } else if game.provider == .steam, game.isInstalled,
                      let url = URL(string: "steam://rungameid/\(game.externalID)") {
                NSWorkspace.shared.open(url)
            } else {
                selectStoreGameAction(game.id)
            }
        }
    }

    private func quickActionTitle(_ item: LibraryItem) -> String {
        if item.running { return "Stop" }
        if item.needsAttention { return "Details" }
        if item.readyToPlay { return "Play" }
        if item.installed { return "Prepare" }
        return "Install"
    }

    private func quickActionSymbol(_ item: LibraryItem) -> String {
        if item.running { return "stop.fill" }
        if item.needsAttention { return "exclamationmark.triangle.fill" }
        if item.readyToPlay { return "play.fill" }
        if item.installed { return "wand.and.stars" }
        return "arrow.down.circle.fill"
    }

    private func statusSymbol(_ item: LibraryItem) -> String {
        if item.needsAttention { return "exclamationmark.triangle.fill" }
        if item.running { return "circle.fill" }
        if item.readyToPlay { return "play.circle.fill" }
        if item.installed { return "checkmark.circle.fill" }
        return "icloud.and.arrow.down"
    }

    private func statusColor(_ item: LibraryItem) -> Color {
        if item.needsAttention { return .orange }
        if item.readyToPlay { return .green }
        return .secondary
    }

    private func playtime(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        if minutes == 0 { return "Not played" }
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%.1f h", Double(minutes) / 60)
    }

    private func clearFilters() {
        sourceFilters = ""
        availabilityFilters = ""
        compatibilityFilters = ""
    }

    private func toggle<Value>(_ value: Value, raw: Binding<String>) where Value: RawRepresentable & Hashable, Value.RawValue == String {
        var values = rawSet(raw.wrappedValue, as: Value.self)
        if values.contains(value) { values.remove(value) } else { values.insert(value) }
        raw.wrappedValue = serialized(values)
    }

    @ViewBuilder private func appContextMenu(_ app: WindowsApplication) -> some View {
        if app.status == .running {
            Button("Stop", systemImage: "stop.fill") { store.toggleRunning(app.id) }
        } else if app.status == .needsAttention {
            Button("Try Again", systemImage: "arrow.clockwise") { store.retry(app.id) }
        } else {
            Button("Open", systemImage: "play.fill") { store.toggleRunning(app.id) }
                .disabled(app.status.isBusy || app.status == .unavailable)
        }
        Divider()
        Button("Show Details", systemImage: "info.circle") { selectAction(app.id) }
        Button("Show in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.executablePath)])
        }
        if developerMode {
            Divider()
            if let environment = store.environment(id: app.environmentID) {
                Button("Open C: Drive", systemImage: "externaldrive") {
                    if let prefix = environment.prefixPath { NSWorkspace.shared.open(URL(fileURLWithPath: prefix).appending(path: "drive_c")) }
                }
                Button("View Logs", systemImage: "doc.text.magnifyingglass") {
                    if let logs = environment.logsPath { NSWorkspace.shared.open(URL(fileURLWithPath: logs)) }
                }
            }
            if app.status == .running { Button("Force Quit", systemImage: "xmark.octagon", role: .destructive) { store.forceQuit(app.id) } }
        }
        Divider()
        Button("Remove…", systemImage: "trash", role: .destructive) { removeCandidate = app }
    }
}

private struct LibraryGroup: Identifiable {
    let id: String
    let title: String?
    let source: LibrarySourceFilter?
    let items: [LibraryItem]
}

private struct ActiveLibraryFilter: Identifiable {
    let id: String
    let title: String
    let remove: () -> Void
}

private func rawSet<Value>(_ raw: String, as type: Value.Type) -> Set<Value> where Value: RawRepresentable & Hashable, Value.RawValue == String {
    Set(raw.split(separator: ",").compactMap { Value(rawValue: String($0)) })
}

private func serialized<Value>(_ values: Set<Value>) -> String where Value: RawRepresentable, Value.RawValue == String {
    values.map(\.rawValue).sorted().joined(separator: ",")
}
