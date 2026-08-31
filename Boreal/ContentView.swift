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
        List {
            Section("Discover") {
                SidebarNavigationRow(
                    title: "Library Home",
                    symbol: "rectangle.grid.2x2.fill",
                    tint: .cyan,
                    isSelected: isLibraryHomeSelected
                ) {
                    showLibraryHome()
                }
                SidebarNavigationRow(
                    title: "Installed",
                    symbol: "arrow.down.to.line.compact",
                    tint: .green,
                    count: installedCount,
                    isSelected: isInstalledSelected,
                    isEnabled: installedCount > 0
                ) {
                    showInstalledLibrary()
                }
                SidebarNavigationRow(
                    title: "Favorites",
                    symbol: "heart.fill",
                    tint: .pink,
                    count: favoriteCount,
                    isSelected: isFavoritesSelected
                ) {
                    showFavoritesLibrary()
                }
            }

            Section("Platforms") {
                ForEach(LibrarySourceFilter.allCases, id: \.self) { source in
                    SidebarNavigationRow(
                        title: source.title,
                        symbol: source.symbol,
                        assetName: source.sidebarAssetName,
                        tint: source.sidebarTint,
                        count: sourceCount(source),
                        isSelected: isSelected(source),
                        isEnabled: sourceCount(source) > 0
                    ) {
                        showLibrary(source: source)
                    }
                }
            }

            Section("Manage") {
                SidebarNavigationRow(
                    title: "Accounts",
                    symbol: "person.crop.circle.badge.checkmark",
                    tint: .indigo,
                    isSelected: selection == .accounts
                ) {
                    showDestination(.accounts)
                }
                SidebarNavigationRow(
                    title: "Downloads",
                    symbol: "arrow.down.circle.fill",
                    tint: .blue,
                    isSelected: selection == .downloads
                ) {
                    showDestination(.downloads)
                }
            }

            if developerMode {
                Section("Developer") {
                    SidebarNavigationRow(
                        title: "Environments",
                        symbol: "externaldrive.fill",
                        tint: .orange,
                        isSelected: selection == .environments
                    ) {
                        showDestination(.environments)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .blue.opacity(0.85), .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                .shadow(color: .cyan.opacity(0.22), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Boreal")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("All your games")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

    private func showDestination(_ destination: SidebarDestination) {
        libraryPath.removeAll()
        selection = destination
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
        libraryProducerFilter = ""
    }

    private func showLibraryHome() {
        showLibrary()
        searchText = ""
        librarySourceFilters = ""
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
    }

    private var installedCount: Int {
        LibraryProjector.makeItems(applications: store.applications, storeGames: store.storeGames)
            .lazy.filter(\.installed).count
    }

    private var isInstalledSelected: Bool {
        selection == .library
            && librarySourceFilters.isEmpty
            && libraryAvailabilityFilters == LibraryAvailabilityFilter.installed.rawValue
    }

    private var isLibraryHomeSelected: Bool {
        selection == .library
            && libraryPath.isEmpty
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

private struct SidebarNavigationRow: View {
    let title: String
    let symbol: String
    var assetName: String? = nil
    let tint: Color
    var count: Int? = nil
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? tint : tint.opacity(0.14))
                    if let assetName {
                        Image(assetName)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(isSelected ? .white : tint)
                            .padding(5)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : tint)
                    }
                }
                .frame(width: 27, height: 27)

                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let count {
                    Text(count.formatted())
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(isSelected ? tint : Color.secondary.opacity(0.62))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? tint.opacity(0.14) : Color.primary.opacity(0.055))
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.16) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.24) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension LibrarySourceFilter {
    var sidebarAssetName: String {
        switch self {
        case .boreal: "BrandWindows"
        case .steam: "BrandSteam"
        case .epic: "BrandEpicGames"
        case .gog: "BrandGOG"
        }
    }

    var sidebarTint: Color {
        switch self {
        case .boreal: .cyan
        case .steam: Color(red: 0.12, green: 0.45, blue: 0.68)
        case .epic: Color(white: 0.32)
        case .gog: Color(red: 0.54, green: 0.27, blue: 0.78)
        }
    }
}

private extension UTType {
    static let windowsExecutable = UTType(filenameExtension: "exe") ?? .data
    static let windowsInstaller = UTType(filenameExtension: "msi") ?? .data
}

#Preview { ContentView().environment(BorealStore(storageURL: URL(fileURLWithPath: "/tmp/boreal-preview.json"))) }
