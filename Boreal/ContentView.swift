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
            guard application.status == .running else { return nil }
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
            Section("Boreal") {
                Label("Library", systemImage: "square.grid.2x2").tag(SidebarDestination.library)
            }
            Section("Services") {
                Label("Accounts", systemImage: "person.crop.circle.badge.checkmark").tag(SidebarDestination.accounts)
                Label("Downloads", systemImage: "arrow.down.circle").tag(SidebarDestination.downloads)
            }
            if developerMode {
                Section("Developer") {
                    Label("Environments", systemImage: "externaldrive").tag(SidebarDestination.environments)
                }
            }
        }
        .listStyle(.sidebar)
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
        case .library:
            LibraryView(
                searchText: $searchText,
                style: libraryStyle,
                sort: librarySort,
                grouping: libraryGrouping,
                sourceFilters: $librarySourceFilters,
                availabilityFilters: $libraryAvailabilityFilters,
                compatibilityFilters: $libraryCompatibilityFilters,
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
                    StoreGameDetailView(game: game)
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
}

private extension UTType {
    static let windowsExecutable = UTType(filenameExtension: "exe") ?? .data
    static let windowsInstaller = UTType(filenameExtension: "msi") ?? .data
}

#Preview { ContentView().environment(BorealStore(storageURL: URL(fileURLWithPath: "/tmp/boreal-preview.json"))) }
