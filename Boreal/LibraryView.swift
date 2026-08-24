import AppKit
import SwiftUI

struct LibraryView: View {
    @Environment(BorealStore.self) private var store
    let searchText: String
    let style: ContentView.LibraryStyle
    let installAction: () -> Void
    let syncSteamAction: () -> Void
    let importAction: (URL) -> Void
    let selectAction: (UUID) -> Void
    let selectStoreGameAction: (UUID) -> Void
    @AppStorage("developerMode") private var developerMode = false
    @State private var removeCandidate: WindowsApplication?

    private var filteredApps: [WindowsApplication] {
        guard !searchText.isEmpty else { return store.applications }
        return store.applications.filter { $0.name.localizedStandardContains(searchText) || $0.publisher.localizedStandardContains(searchText) }
    }

    private var filteredStoreGames: [StoreLibraryGame] {
        guard !searchText.isEmpty else { return store.storeGames }
        return store.storeGames.filter {
            $0.name.localizedStandardContains(searchText)
                || ($0.developer?.localizedStandardContains(searchText) ?? false)
        }
    }

    var body: some View {
        Group {
            if store.applications.isEmpty && store.storeGames.isEmpty {
                BorealEmptyState(action: installAction, steamAction: syncSteamAction)
            }
            else if filteredApps.isEmpty && filteredStoreGames.isEmpty { ContentUnavailableView.search(text: searchText) }
            else if style == .grid { grid }
            else { list }
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
        } message: {
            Text("This removes the app from Boreal. The original setup file is not deleted.")
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(GameLibraryProvider.allCases, id: \.self) { provider in
                    let games = filteredStoreGames.filter { $0.provider == provider }
                    if !games.isEmpty { storeGridSection(provider: provider, games: games) }
                }
                if searchText.isEmpty, !recentApps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Used").font(.title3).fontWeight(.semibold)
                        HStack(spacing: 14) {
                            ForEach(recentApps) { app in
                                Button { selectAction(app.id) } label: {
                                    HStack(spacing: 10) {
                                        AppIconView(symbol: app.iconSymbol, size: 38)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name).fontWeight(.medium).lineLimit(1)
                                            ApplicationStatusLabel(status: app.status, subtle: true)
                                        }
                                    }
                                    .padding(10)
                                    .frame(width: 190, alignment: .leading)
                                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 11))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !filteredApps.isEmpty { VStack(alignment: .leading, spacing: 16) {
                    if searchText.isEmpty { Text("All Apps").font(.title3).fontWeight(.semibold) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 30)], spacing: 30) {
                        ForEach(filteredApps) { app in
                            Button { selectAction(app.id) } label: {
                                VStack(spacing: 11) {
                                    AppIconView(symbol: app.iconSymbol, size: 104)
                                    VStack(spacing: 3) {
                                        Text(app.name).font(.headline).lineLimit(1)
                                        ApplicationStatusLabel(status: app.status, subtle: true)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { appContextMenu(app) }
                            .accessibilityLabel("\(app.name), \(app.status.rawValue)")
                        }
                    }
                } }
            }
            .padding(32)
            .frame(maxWidth: 1100)
        }
    }

    private var list: some View {
        List {
            ForEach(GameLibraryProvider.allCases, id: \.self) { provider in
                let games = filteredStoreGames.filter { $0.provider == provider }
                if !games.isEmpty {
                    Section {
                    ForEach(games) { game in
                        Button { selectStoreGameAction(game.id) } label: {
                            HStack(spacing: 12) {
                                GameArtworkView(game: game, width: 38, height: 52)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(game.name).fontWeight(.medium)
                                    Text(game.developer ?? game.provider.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if provider == .steam { CommunityCompatibilityBadge(profile: game.compatibility, compact: true) }
                                Text(game.isInstalled ? "Installed" : provider.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                } header: {
                    HStack { Text("\(provider.rawValue) Library"); Spacer(); syncButton(for: provider) }
                }
                }
            }
            if !filteredApps.isEmpty {
                Section("Windows Apps") {
                    ForEach(filteredApps) { app in
                        Button { selectAction(app.id) } label: {
                            HStack(spacing: 12) {
                                AppIconView(symbol: app.iconSymbol, size: 36)
                                Text(app.name)
                                Spacer()
                                ApplicationStatusLabel(status: app.status, subtle: true)
                                CompatibilityLabel(rating: app.compatibility)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { appContextMenu(app) }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func storeGridSection(provider: GameLibraryProvider, games: [StoreLibraryGame]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(provider.rawValue) Library", systemImage: provider == .steam ? "gamecontroller.fill" : "e.square.fill")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                syncButton(for: provider)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 156, maximum: 184), spacing: 26)], spacing: 28) {
                ForEach(games) { game in
                    Button { selectStoreGameAction(game.id) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            GameArtworkView(game: game, width: 156, height: 218)
                            Text(game.name).font(.headline).lineLimit(1)
                            HStack(spacing: 5) {
                                Image(systemName: game.isInstalled ? "checkmark.circle.fill" : "cloud")
                                Text(game.isInstalled ? "Installed" : game.provider.rawValue)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if provider == .steam { CommunityCompatibilityBadge(profile: game.compatibility, compact: true) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(game.name), \(game.provider.rawValue)")
                }
            }
        }
    }

    @ViewBuilder private func syncButton(for provider: GameLibraryProvider) -> some View {
        if libraryIsSyncing(provider) {
            ProgressView().controlSize(.small).help("Importing \(provider.rawValue) Library")
        } else {
            Button("Refresh", systemImage: "arrow.clockwise") {
                if provider == .steam { syncSteamAction() } else { store.syncEpicLibrary() }
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless).help("Refresh \(provider.rawValue) Library")
        }
    }

    private func libraryIsSyncing(_ provider: GameLibraryProvider) -> Bool {
        if case .syncing(let syncingProvider) = store.librarySyncState { return syncingProvider == provider }
        return false
    }

    private var recentApps: [WindowsApplication] {
        Array(store.applications.filter { $0.lastOpened != nil }.sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }.prefix(3))
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
            if app.status == .running {
                Button("Force Quit", systemImage: "xmark.octagon", role: .destructive) { store.forceQuit(app.id) }
            }
        }
        Divider()
        Button("Remove…", systemImage: "trash", role: .destructive) { removeCandidate = app }
    }
}
