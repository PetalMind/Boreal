//
//  ContentView.swift
//  Boreal
//
//  Created by Dominik on 24/08/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(BorealStore.self) private var store
    @State private var selection: SidebarDestination? = .library
    @State private var libraryPath: [LibraryRoute] = []
    @State private var searchText = ""
    @AppStorage("libraryStyle") private var libraryStyle = LibraryStyle.grid
    @AppStorage("librarySort") private var librarySort = LibrarySort.nameAscending
    @AppStorage("libraryGrouping") private var libraryGrouping = LibraryGrouping.source
    @AppStorage("librarySourceFilters") private var librarySourceFilters = ""
    @AppStorage("libraryAvailabilityFilters") private var libraryAvailabilityFilters = ""
    @AppStorage("libraryCompatibilityFilters") private var libraryCompatibilityFilters = ""
    @AppStorage("libraryProducerFilter") private var libraryProducerFilter = ""
    @State private var showsImporter = false
    @State private var installCandidate: InstallCandidate?
    @State private var showsNewEnvironment = false
    @State private var newEnvironmentName = ""
    @AppStorage("developerMode") private var developerMode = false

    enum LibraryStyle: String, CaseIterable { case grid, list }

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            NavigationStack(path: $libraryPath) {
                ZStack {
                    BorealGlassBackdrop()
                    destinationView
                }
                .frame(minWidth: 640, minHeight: 500)
                .navigationTitle(title)
                .toolbar { toolbarContent }
                .navigationDestination(for: LibraryRoute.self) { route in
                    routeView(route)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.windowsExecutable, .windowsInstaller], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { installCandidate = InstallCandidate(url: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .installWindowsApp)) { _ in showsImporter = true }
        .onReceive(NotificationCenter.default.publisher(for: .showLibraryGrid)) { _ in showLibrary(style: .grid) }
        .onReceive(NotificationCenter.default.publisher(for: .showLibraryList)) { _ in showLibrary(style: .list) }
        .onChange(of: runningOverlayGames, initial: true) { _, games in
            GameOverlayController.shared.synchronize(games: games)
        }
        .sheet(item: $installCandidate) { candidate in
            InstallationSheet(candidate: candidate) { installedID in showLibrary(route: .application(installedID)) }.environment(store)
        }
        .alert("New Environment", isPresented: $showsNewEnvironment) {
            TextField("Name", text: $newEnvironmentName)
            Button("Cancel", role: .cancel) { newEnvironmentName = "" }
            Button("Create") {
                store.createEnvironment(named: newEnvironmentName.isEmpty ? "New Environment" : newEnvironmentName)
                newEnvironmentName = ""
                libraryPath.removeAll()
                selection = .environments
            }
        } message: { Text("Create an empty, isolated Windows environment.") }
        .sheet(item: $store.presentedIssue) { issue in
            BorealErrorSheet(
                issue: issue,
                retry: issue.retryApplicationID.map { id in { store.retry(id) } },
                dismiss: { store.presentedIssue = nil }
            )
        }
    }

    private var runningOverlayGames: [OverlayGame] {
        store.applications.compactMap { application in
            guard application.status == .running, !application.isSteamRuntimeHost else { return nil }
            return OverlayGame(
                id: application.id,
                name: application.name,
                launchedAt: application.lastOpened ?? .distantPast,
                performanceLogURL: store.performanceLogURL(for: application.id),
                graphics: application.graphics
            )
        }
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section {
                Button {
                    showLibrary()
                    librarySourceFilters = ""
                    libraryAvailabilityFilters = ""
                    libraryCompatibilityFilters = ""
                    libraryProducerFilter = ""
                } label: {
                    BorealSidebarRow(
                        title: "Home",
                        subtitle: "All your games",
                        symbol: "rectangle.grid.2x2.fill",
                        tint: .cyan,
                        isSelected: isHomeSelected
                    )
                }
                .buttonStyle(.plain)
                .tag(SidebarDestination.library)
                Button {
                    showInstalledLibrary()
                } label: {
                    BorealSidebarRow(
                        title: "Installed",
                        subtitle: "Ready on this Mac",
                        symbol: "arrow.down.circle.fill",
                        tint: .green,
                        count: installedCount,
                        isSelected: isInstalledSelected
                    )
                }
                .buttonStyle(.plain)
                .disabled(installedCount == 0)
                .accessibilityAddTraits(isInstalledSelected ? .isSelected : [])
                Button {
                    showFavoritesLibrary()
                } label: {
                    BorealSidebarRow(
                        title: "Favorites",
                        subtitle: "Your collection",
                        symbol: "heart.fill",
                        tint: .pink,
                        count: favoriteCount,
                        isSelected: isFavoritesSelected
                    )
                }
                .buttonStyle(.plain)
                .tag(SidebarDestination.favorites)
                .accessibilityAddTraits(isFavoritesSelected ? .isSelected : [])
            } header: {
                BorealSidebarSectionHeader("Library")
            }

            Section {
                ForEach(LibrarySourceFilter.allCases, id: \.self) { source in
                    Button {
                        showLibrary(source: source)
                    } label: {
                        BorealStoreSidebarRow(
                            source: source,
                            count: sourceCount(source),
                            isSelected: isSelected(source)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sourceCount(source) == 0)
                    .accessibilityAddTraits(isSelected(source) ? .isSelected : [])
                }
            } header: {
                BorealSidebarSectionHeader("Sources")
            }

            Section {
                Label("Accounts", systemImage: "person.crop.circle.badge.checkmark").tag(SidebarDestination.accounts)
                Label("Downloads", systemImage: "arrow.down.circle").tag(SidebarDestination.downloads)
            } header: {
                BorealSidebarSectionHeader("Services")
            }
            if developerMode {
                Section("Developer") {
                    Label("Environments", systemImage: "externaldrive").tag(SidebarDestination.environments)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.cyan.gradient)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                .shadow(color: .cyan.opacity(0.24), radius: 7, y: 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text("BOREAL")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .tracking(1.1)
                    Text("One library. Every world.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                selection = .downloads
                libraryPath.removeAll()
            } label: {
                HStack(spacing: 7) {
                    if store.runtimeOperationDetail != nil {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: runtimeFooter.symbol)
                            .foregroundStyle(runtimeFooter.tint)
                    }
                    Text(runtimeFooter.title)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(runtimeFooter.help)
            .padding()
        }
    }

    @ViewBuilder private var destinationView: some View {
        switch selection ?? .library {
        case .library, .favorites:
            LibraryView(
                searchText: $searchText,
                style: libraryStyle,
                sort: librarySort,
                grouping: libraryGrouping,
                sourceFilters: $librarySourceFilters,
                availabilityFilters: $libraryAvailabilityFilters,
                compatibilityFilters: $libraryCompatibilityFilters,
                producerFilter: $libraryProducerFilter,
                favoritesOnly: selection == .favorites,
                installAction: { showsImporter = true },
                syncSteamAction: { store.syncSteamLibrary() },
                importAction: { installCandidate = InstallCandidate(url: $0) },
                selectAction: { libraryPath.append(.application($0)) },
                selectStoreGameAction: { libraryPath.append(.storeGame($0)) }
            )
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search Library")
        case .accounts: AccountsView()
        case .environments: EnvironmentsView { showsNewEnvironment = true }
        case .downloads: DownloadsView()
        }
    }

    @ViewBuilder private func routeView(_ route: LibraryRoute) -> some View {
        ZStack {
            BorealGlassBackdrop()
            switch route {
            case .application(let id):
                if let app = store.application(id: id) {
                    AppDetailView(app: app) { libraryPath.removeAll() }
                        .navigationTitle(app.name)
                } else {
                    ContentUnavailableView("App Not Found", systemImage: "questionmark.app")
                        .navigationTitle("App")
                }
            case .storeGame(let id):
                if let game = store.storeGame(id: id) {
                    StoreGameDetailView(game: game) { producer in
                        libraryProducerFilter = producer
                        libraryPath.removeAll()
                    }
                        .navigationTitle(game.name)
                } else {
                    ContentUnavailableView("Game Not Found", systemImage: "questionmark.app")
                        .navigationTitle("Game")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 500)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if selection == .library && libraryPath.isEmpty {
            ToolbarItemGroup(placement: .primaryAction) {
                LibraryToolbarControls(
                    style: $libraryStyle,
                    sort: $librarySort,
                    grouping: $libraryGrouping,
                    sourceFilters: $librarySourceFilters,
                    availabilityFilters: $libraryAvailabilityFilters,
                    compatibilityFilters: $libraryCompatibilityFilters
                )
            }
        }
        if (selection == .library && libraryPath.isEmpty) || (developerMode && selection == .environments) {
            ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Install Windows App…", systemImage: "shippingbox") { showsImporter = true }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Import Steam Library", systemImage: "arrow.triangle.2.circlepath") { store.syncSteamLibrary() }
                    .disabled({ if case .syncing = store.librarySyncState { true } else { false } }())
                if developerMode {
                    Divider()
                    Button("Create Empty Environment…", systemImage: "externaldrive.badge.plus") { showsNewEnvironment = true }
                }
            } label: { Label("Add", systemImage: "plus") }
            .menuIndicator(.hidden)
            .help(developerMode ? "Install an app or create an environment" : "Install a Windows app")
            }
        }
    }

    private var title: String {
        switch selection ?? .library {
        case .library: "Library"
        case .favorites: "Favorites"
        case .accounts: "Accounts"
        case .environments: "Environments"
        case .downloads: "Downloads"
        }
    }

    private var runtimeFooter: (title: String, symbol: String, tint: Color, help: String) {
        if store.runtimeOperationDetail != nil {
            return ("Preparing Runtime", "shippingbox", .accentColor, "Show runtime preparation")
        }
        if store.runtimeStatuses.contains(where: { $0.source == .installed && $0.isVerified }) {
            return ("Runtime Ready", "checkmark.circle.fill", .green, "Show the verified Windows runtime")
        }
        if !store.localRuntimeCandidates.isEmpty {
            return ("Wine Detected", "shippingbox.and.arrow.backward.fill", .cyan, "Boreal can prepare the detected Wine automatically")
        }
        if store.runtimeStatuses.contains(where: { $0.state == .available }) {
            return ("Runtime Available", "arrow.down.circle.fill", .accentColor, "Download the Windows runtime")
        }
        return ("Runtime Setup Needed", "shippingbox", .orange, "Open runtime setup")
    }

    private var sidebarSelection: Binding<SidebarDestination?> {
        Binding(
            get: { selection },
            set: { destination in
                libraryPath.removeAll()
                selection = destination
            }
        )
    }

    private func showLibrary(style: LibraryStyle? = nil, route: LibraryRoute? = nil) {
        if let style { libraryStyle = style }
        selection = .library
        libraryPath = route.map { [$0] } ?? []
    }

    private func showLibrary(source: LibrarySourceFilter) {
        selection = .library
        libraryPath.removeAll()
        searchText = ""
        librarySourceFilters = source.rawValue
        libraryAvailabilityFilters = ""
        libraryCompatibilityFilters = ""
        libraryProducerFilter = ""
    }

    private func showInstalledLibrary() {
        selection = .library
        libraryPath.removeAll()
        searchText = ""
        librarySourceFilters = ""
        libraryAvailabilityFilters = LibraryAvailabilityFilter.installed.rawValue
        libraryCompatibilityFilters = ""
        libraryProducerFilter = ""
    }

    private func showFavoritesLibrary() {
        selection = .favorites
        libraryPath.removeAll()
        searchText = ""
        librarySourceFilters = ""
        libraryAvailabilityFilters = ""
        libraryCompatibilityFilters = ""
        libraryProducerFilter = ""
    }

    private func sourceCount(_ source: LibrarySourceFilter) -> Int {
        LibraryProjector.makeItems(applications: store.applications, storeGames: store.storeGames)
            .lazy.filter { $0.source == source }.count
    }

    private func isSelected(_ source: LibrarySourceFilter) -> Bool {
        selection == .library
            && librarySourceFilters == source.rawValue
            && libraryAvailabilityFilters.isEmpty
            && libraryCompatibilityFilters.isEmpty
    }

    private var installedCount: Int {
        LibraryProjector.makeItems(applications: store.applications, storeGames: store.storeGames)
            .lazy.filter(\.installed).count
    }

    private var isInstalledSelected: Bool {
        selection == .library
            && librarySourceFilters.isEmpty
            && libraryAvailabilityFilters == LibraryAvailabilityFilter.installed.rawValue
            && libraryCompatibilityFilters.isEmpty
    }

    private var isHomeSelected: Bool {
        selection == .library
            && librarySourceFilters.isEmpty
            && libraryAvailabilityFilters.isEmpty
            && libraryCompatibilityFilters.isEmpty
            && libraryProducerFilter.isEmpty
    }

    private var isFavoritesSelected: Bool { selection == .favorites }

    private var favoriteCount: Int {
        let items = LibraryProjector.makeItems(applications: store.applications, storeGames: store.storeGames)
        return items.lazy.filter { store.favoriteKeys.contains($0.favoriteKey) }.count
    }
}

private struct BorealSidebarSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.15)
            .foregroundStyle(.tertiary)
    }
}

private struct BorealSidebarRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var count: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(isSelected ? 0.26 : 0.14))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : tint.opacity(0.88))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(isSelected ? .semibold : .medium))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 4)
            if let count {
                Text(count.formatted())
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(isSelected ? tint : Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(selectionBackground)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: 3).padding(.vertical, 7)
                }
        }
    }
}

private struct BorealStoreSidebarRow: View {
    let source: LibrarySourceFilter
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            BorealStoreMark(source: source, isSelected: isSelected)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                Text(source.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            Text(count.formatted())
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(isSelected ? source.brandColor : Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(source.brandColor.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(source.brandColor).frame(width: 3).padding(.vertical, 7)
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BorealStoreMark: View {
    let source: LibrarySourceFilter
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(source.brandGradient)
            if let assetName = source.brandAssetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(source == .epic ? 5 : 6)
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.28 : 0.12), lineWidth: 0.75)
        }
        .shadow(color: source.brandColor.opacity(isSelected ? 0.28 : 0.10), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

private extension LibrarySourceFilter {
    var subtitle: String {
        switch self {
        case .boreal: "Local Windows apps"
        case .steam: "Steam library"
        case .epic: "Epic collection"
        case .gog: "DRM-free games"
        }
    }

    var brandAssetName: String? {
        switch self {
        case .boreal: nil
        case .steam: "SteamLogo"
        case .epic: "EpicGamesLogo"
        case .gog: "GOGLogo"
        }
    }

    var brandColor: Color {
        switch self {
        case .boreal: .cyan
        case .steam: Color(red: 0.12, green: 0.53, blue: 0.78)
        case .epic: Color(red: 0.42, green: 0.43, blue: 0.47)
        case .gog: Color(red: 0.60, green: 0.29, blue: 0.82)
        }
    }

    var brandGradient: LinearGradient {
        switch self {
        case .boreal:
            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .steam:
            LinearGradient(colors: [Color(red: 0.10, green: 0.18, blue: 0.29), Color(red: 0.10, green: 0.55, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .epic:
            LinearGradient(colors: [Color(red: 0.18, green: 0.18, blue: 0.20), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gog:
            LinearGradient(colors: [Color(red: 0.39, green: 0.18, blue: 0.56), Color(red: 0.74, green: 0.32, blue: 0.77)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private extension UTType {
    static let windowsExecutable = UTType(filenameExtension: "exe") ?? .data
    static let windowsInstaller = UTType(filenameExtension: "msi") ?? .data
}

#Preview { ContentView().environment(BorealStore(storageURL: URL(fileURLWithPath: "/tmp/boreal-preview.json"))) }
