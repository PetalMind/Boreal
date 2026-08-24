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
    @State private var searchText = ""
    @State private var libraryStyle = LibraryStyle.grid
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
            destinationView
                .frame(minWidth: 640, minHeight: 500)
                .navigationTitle(title)
                .toolbar { toolbarContent }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Library")
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.windowsExecutable, .windowsInstaller], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { installCandidate = InstallCandidate(url: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .installWindowsApp)) { _ in showsImporter = true }
        .onReceive(NotificationCenter.default.publisher(for: .showLibraryGrid)) { _ in libraryStyle = .grid; selection = .library }
        .onReceive(NotificationCenter.default.publisher(for: .showLibraryList)) { _ in libraryStyle = .list; selection = .library }
        .sheet(item: $installCandidate) { candidate in
            InstallationSheet(candidate: candidate) { installedID in selection = .application(installedID) }.environment(store)
        }
        .alert("New Environment", isPresented: $showsNewEnvironment) {
            TextField("Name", text: $newEnvironmentName)
            Button("Cancel", role: .cancel) { newEnvironmentName = "" }
            Button("Create") {
                store.createEnvironment(named: newEnvironmentName.isEmpty ? "New Environment" : newEnvironmentName)
                newEnvironmentName = ""
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

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Boreal") {
                Label("Library", systemImage: "square.grid.2x2").tag(SidebarDestination.library)
                Label("Accounts", systemImage: "person.crop.circle.badge.checkmark").tag(SidebarDestination.accounts)
            }
            Section {
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
            Label("Designed for Apple Silicon", systemImage: "cpu").font(.caption).foregroundStyle(.secondary).padding()
        }
    }

    @ViewBuilder private var destinationView: some View {
        switch selection ?? .library {
        case .library:
            LibraryView(
                searchText: searchText,
                style: libraryStyle,
                installAction: { showsImporter = true },
                syncSteamAction: { store.syncSteamLibrary() },
                importAction: { installCandidate = InstallCandidate(url: $0) },
                selectAction: { selection = .application($0) },
                selectStoreGameAction: { selection = .storeGame($0) }
            )
        case .accounts: AccountsView()
        case .environments: EnvironmentsView { showsNewEnvironment = true }
        case .downloads: DownloadsView()
        case .application(let id):
            if let app = store.application(id: id) { AppDetailView(app: app) { selection = .library } }
            else { ContentUnavailableView("App Not Found", systemImage: "questionmark.app") }
        case .storeGame(let id):
            if let game = store.storeGame(id: id) { StoreGameDetailView(game: game) }
            else { ContentUnavailableView("Game Not Found", systemImage: "questionmark.app") }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if selection == .library || developerMode {
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
        case .application(let id): store.application(id: id)?.name ?? "App"
        case .storeGame(let id): store.storeGame(id: id)?.name ?? "Game"
        }
    }
}

private extension UTType {
    static let windowsExecutable = UTType(filenameExtension: "exe") ?? .data
    static let windowsInstaller = UTType(filenameExtension: "msi") ?? .data
}

#Preview { ContentView().environment(BorealStore(storageURL: URL(fileURLWithPath: "/tmp/boreal-preview.json"))) }
