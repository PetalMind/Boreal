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
        .alert("Boreal", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Boreal") { Label("Library", systemImage: "square.grid.2x2").tag(SidebarDestination.library) }
            if !store.applications.isEmpty {
                Section("Recent") {
                    ForEach(store.applications.sorted(by: recentSort).prefix(4)) { app in
                        Label(app.name, systemImage: app.iconSymbol).tag(SidebarDestination.application(app.id))
                    }
                }
            }
            Section("Tools") {
                Label("Environments", systemImage: "externaldrive").tag(SidebarDestination.environments)
                Label("Downloads", systemImage: "arrow.down.circle").tag(SidebarDestination.downloads)
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
            LibraryView(searchText: searchText, style: libraryStyle, installAction: { showsImporter = true }, importAction: { installCandidate = InstallCandidate(url: $0) }) { selection = .application($0) }
        case .environments: EnvironmentsView { showsNewEnvironment = true }
        case .downloads: DownloadsView()
        case .application(let id):
            if let app = store.application(id: id) { AppDetailView(app: app) { selection = .library } }
            else { ContentUnavailableView("App Not Found", systemImage: "questionmark.app") }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if selection == .library {
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $libraryStyle) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(LibraryStyle.grid)
                    Label("List", systemImage: "list.bullet").tag(LibraryStyle.list)
                }.pickerStyle(.segmented).labelsHidden()
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Install Windows App…", systemImage: "shippingbox") { showsImporter = true }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Create Empty Environment…", systemImage: "externaldrive.badge.plus") { showsNewEnvironment = true }
            } label: { Label("Add", systemImage: "plus") }
            .menuIndicator(.hidden)
            .help("Install an app or create an environment")
        }
    }

    private var title: String {
        switch selection ?? .library {
        case .library: "Library"
        case .environments: "Environments"
        case .downloads: "Downloads"
        case .application(let id): store.application(id: id)?.name ?? "App"
        }
    }

    private func recentSort(_ lhs: WindowsApplication, _ rhs: WindowsApplication) -> Bool { (lhs.lastOpened ?? .distantPast) > (rhs.lastOpened ?? .distantPast) }
}

private extension UTType {
    static let windowsExecutable = UTType(filenameExtension: "exe") ?? .data
    static let windowsInstaller = UTType(filenameExtension: "msi") ?? .data
}

#Preview { ContentView().environment(BorealStore(storageURL: URL(fileURLWithPath: "/tmp/boreal-preview.json"))) }
