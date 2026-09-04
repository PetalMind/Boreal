import AppKit
import SwiftUI

/// A deliberately separate presentation layer for controller-first use. The
/// desktop split view remains unchanged; this view owns its own hierarchy and
/// keeps the focused item stable while the user visits a game.
struct ConsoleModeView: View {
    @Environment(BorealStore.self) private var store
    @State private var section = ConsoleSection.home
    @State private var focusedID: LibraryItem.ID?
    @State private var selectedItem: LibraryItem.ID?
    @State private var showsOnboarding = !UserDefaults.standard.bool(forKey: "consoleModeOnboardingShown")
    @State private var showsGameMenu = false
    @State private var showsQuickMenu = false
    @AppStorage("consoleModeEnabled") private var consoleModeEnabled = false
    @AppStorage("consoleModeAutoEnter") private var consoleModeAutoEnter = true
    @AppStorage("consoleModeReturnAfterGame") private var consoleModeReturnAfterGame = true
    let exit: () -> Void

    private var items: [LibraryItem] {
        LibraryProjector.makeItems(applications: store.applications, storeGames: store.storeGames)
            .filter { item in
                switch section {
                case .installed: item.installed
                case .recent: item.lastUsed != nil
                case .favorites: store.favoriteKeys.contains(item.favoriteKey)
                default: true
                }
            }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }

    private var focusedItem: LibraryItem? { items.first { $0.id == focusedID } }

    private var selectedApplication: WindowsApplication? {
        guard let selectedItem else { return nil }
        switch selectedItem {
        case .application(let id): return store.application(id: id)
        case .storeGame(let id):
            guard let game = store.storeGame(id: id) else { return nil }
            return store.linkedApplication(for: game)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.045, blue: 0.095), Color(red: 0.008, green: 0.012, blue: 0.025), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()
            Circle().fill(.cyan.opacity(0.07)).frame(width: 900, height: 900).blur(radius: 140).offset(x: -560, y: -420)
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        if selectedItem == nil {
                            Text(section.title)
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .tracking(-1.1)
                        }
                        if let selectedItem {
                            ConsoleGameDetailView(
                                item: items.first { $0.id == selectedItem },
                                close: { self.selectedItem = nil }
                            )
                        } else {
                            sectionContent
                        }
                    }
                    .frame(maxWidth: 1900, alignment: .leading)
                    .padding(.horizontal, 72)
                    .padding(.top, 42)
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                footer
            }
            .foregroundStyle(.white)
        }
        .sheet(isPresented: $showsOnboarding) { onboarding }
        .confirmationDialog("Game Options", isPresented: $showsGameMenu, titleVisibility: .visible) { gameActionButtons }
        .sheet(isPresented: $showsQuickMenu) { quickMenu }
        .onReceive(NotificationCenter.default.publisher(for: .borealControllerInputPressed)) { note in
            guard let input = note.object as? ControllerInput else { return }
            handle(input)
        }
        .onReceive(NotificationCenter.default.publisher(for: .borealControllerQuickMenu)) { _ in
            showsQuickMenu = true
        }
        .onChange(of: section) { _, _ in
            selectedItem = nil
            focusedID = items.first?.id
        }
        .onAppear { focusedID = items.first?.id }
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .home: homeSections
        case .downloads: downloadsContent
        case .activity: activityContent
        case .settings: settingsContent
        default: gameRail(title: section.title, values: items)
        }
    }

    private var header: some View {
        HStack(spacing: 38) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(.cyan)
                Text("BOREAL").font(.system(size: 28, weight: .black, design: .rounded)).tracking(2.4)
            }
            HStack(spacing: 8) {
                ForEach(ConsoleSection.allCases) { value in
                    Button(value.title) { section = value }
                        .buttonStyle(ConsoleNavButtonStyle(selected: section == value))
                }
            }
            Spacer()
            Text(Date.now, style: .time).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            Button("Exit", systemImage: "rectangle.portrait.and.arrow.right", action: exit)
                .buttonStyle(.bordered).controlSize(.large)
        }
        .frame(maxWidth: 1900)
        .padding(.horizontal, 72).padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.18))
    }

    @ViewBuilder private var homeSections: some View {
        if let featured = items.first(where: { $0.lastUsed != nil }) ?? items.first {
            ConsoleHomeHero(item: featured) {
                focusedID = featured.id
                selectedItem = featured.id
            }
        }
        let recent = Array(items.prefix(8))
        if !recent.isEmpty { gameRail(title: "Recently Added", values: recent) }
        let favorites = items.filter { store.favoriteKeys.contains($0.favoriteKey) }.prefix(8).map { $0 }
        if !favorites.isEmpty { gameRail(title: "Favorites", values: favorites) }
        let ready = items.filter(\.readyToPlay).prefix(8).map { $0 }
        if !ready.isEmpty { gameRail(title: "Installed & Ready", values: ready) }
        attentionSection
        downloadsSummary
    }

    private func gameRail(title: String, values: [LibraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(values.count.formatted()).font(.callout.bold().monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(.white.opacity(0.08), in: Capsule())
            }
            if values.isEmpty {
                Text("Nothing here yet.").foregroundStyle(.secondary).font(.title3)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 22) {
                        ForEach(values) { item in
                            ConsoleGameCard(item: item, focused: focusedID == item.id) {
                                focusedID = item.id
                                selectedItem = item.id
                            }
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 8)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, -8, for: .scrollContent)
            }
        }
        .padding(.top, 6)
    }

    private var attentionSection: some View {
        let values = items.filter(\.needsAttention)
        return Group {
            if !values.isEmpty { gameRail(title: "Needs Attention", values: values) }
        }
    }

    private var downloadsSummary: some View {
        Group {
            if !store.storeGameOperations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Downloads").font(.title2.bold())
                    ForEach(Array(store.storeGameOperations.keys.prefix(3)), id: \.self) { key in
                        Text(key).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var downloadsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Download Queue").font(.title2.bold())
            if store.activeStoreGameOperations.isEmpty {
                Text("No active downloads.").font(.title3).foregroundStyle(.secondary)
            } else {
                ForEach(store.activeStoreGameOperations, id: \.game.id) { operation in
                    HStack(spacing: 18) {
                        Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(operation.game.name).font(.title3.weight(.semibold))
                            Text(operation.state.progress.map { progressText($0) } ?? "Preparing")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(operation.state.isCancellable ? "Pause" : "Resume").foregroundStyle(.cyan)
                    }
                    .padding(18).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recent activity").font(.title2.bold())
            ForEach(items.filter { $0.lastUsed != nil }.prefix(8)) { item in
                HStack {
                    Image(systemName: item.running ? "play.circle.fill" : "clock").foregroundStyle(item.running ? .green : .secondary)
                    Text(item.name).font(.title3.weight(.medium))
                    Spacer()
                    Text(item.lastUsed ?? .distantPast, style: .relative).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Fullscreen settings").font(.title2.bold())
            Toggle("Keep TV mode enabled", isOn: $consoleModeEnabled)
                .font(.title3).toggleStyle(.switch).padding(18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Toggle("Enter when a controller connects", isOn: $consoleModeAutoEnter)
                .font(.title3).toggleStyle(.switch).padding(18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Toggle("Return after a game exits", isOn: $consoleModeReturnAfterGame)
                .font(.title3).toggleStyle(.switch).padding(18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            settingRow("Controller", value: controllerStatus)
            settingRow("Navigation", value: "D-pad / left stick")
            settingRow("Confirm / Back / Menu", value: "A / B / Y")
        }
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack { Text(title).font(.title3); Spacer(); Text(value).foregroundStyle(.secondary) }
            .padding(18).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var controllerStatus: String {
        if let controller = ControllerManager.shared.controllers.first { return "\(controller.name) · Connected" }
        return "No controller detected"
    }

    private func progressText(_ progress: StoreGameOperationProgress) -> String {
        if let fraction = progress.clampedFraction { return "\(Int(fraction * 100))% downloaded" }
        return progress.message
    }

    private var footer: some View {
        HStack {
            ConsoleControlHint(key: "✚", label: "Navigate")
            ConsoleControlHint(key: "A", label: "Select")
            ConsoleControlHint(key: "B", label: "Back")
            ConsoleControlHint(key: "X", label: "Favorite")
            ConsoleControlHint(key: "Y", label: "Options")
            Spacer()
            Label(controllerStatus, systemImage: "gamecontroller.fill").foregroundStyle(.secondary)
        }
        .frame(maxWidth: 1900)
        .font(.callout.weight(.semibold)).padding(.horizontal, 72).padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.72))
    }

    private var onboarding: some View {
        VStack(spacing: 18) {
            Image(systemName: "gamecontroller.fill").font(.system(size: 48)).foregroundStyle(.cyan)
            Text("Welcome to Boreal Fullscreen").font(.title.bold())
            Text("Use your controller to navigate.\nA Select · B Back · Y More options")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Continue") {
                UserDefaults.standard.set(true, forKey: "consoleModeOnboardingShown")
                showsOnboarding = false
            }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(42).frame(minWidth: 420)
    }

    private func handle(_ input: ControllerInput) {
        switch input {
        case .leftShoulder: section = ConsoleSection.allCases[max(0, section.index - 1)]
        case .rightShoulder: section = ConsoleSection.allCases[min(ConsoleSection.allCases.count - 1, section.index + 1)]
        case .dpadLeft, .leftStickLeft: moveFocus(by: -1)
        case .dpadRight, .leftStickRight: moveFocus(by: 1)
        case .dpadUp, .leftStickUp: moveFocus(by: -4)
        case .dpadDown, .leftStickDown: moveFocus(by: 4)
        case .buttonA:
            if selectedItem != nil { activateSelectedGame() }
            else { selectedItem = focusedID }
        case .buttonB:
            if selectedItem != nil { selectedItem = nil }
            else { exit() }
        case .buttonX:
            if let item = focusedItem { store.toggleFavorite(key: item.favoriteKey) }
        case .buttonY: showsGameMenu = true
        default: break
        }
    }

    private func moveFocus(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = focusedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        focusedID = items[min(max(0, current + offset), items.count - 1)].id
    }

    private func activateSelectedGame() {
        guard let item = focusedItem else { return }
        switch item.id {
        case .application(let id): store.toggleRunning(id)
        case .storeGame(let id):
            guard let game = store.storeGame(id: id) else { return }
            if let application = store.linkedApplication(for: game) {
                store.toggleRunning(application.id)
            } else if game.isInstalled, game.installedPlatform == .nativeMacOS {
                openNativeGame(game)
            } else if !game.isInstalled {
                install(game)
            } else {
                // A Windows store installation without a linked Boreal
                // application still needs the normal environment preparation
                // flow exposed by the store detail view.
                store.prepareStoreGame(game)
            }
        }
    }

    private func openNativeGame(_ game: StoreLibraryGame) {
        guard let path = game.installPath else { return }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ), let app = enumerator.first(where: { ($0 as? URL)?.pathExtension.caseInsensitiveCompare("app") == .orderedSame }) as? URL {
            GameOverlayController.shared.expectNativeGame(name: game.name, installationURL: app)
            NSWorkspace.shared.open(app)
        } else {
            NSWorkspace.shared.open(root)
        }
    }

    @ViewBuilder private var gameActionButtons: some View {
        if let item = focusedItem {
            switch item.id {
            case .application(let id):
                let isRunning = store.application(id: id)?.status == .running
                Button(isRunning ? "Stop Game" : "Play") { store.toggleRunning(id) }
                if isRunning {
                    Button("Open Overlay") { GameOverlayController.shared.toggleVisibility() }
                }
            case .storeGame(let id):
                if let game = store.storeGame(id: id) {
                    if let app = store.linkedApplication(for: game) {
                        Button(app.status == .running ? "Stop Game" : "Play") { store.toggleRunning(app.id) }
                    } else if game.isInstalled == false {
                        Button("Install") { install(game) }
                    }
                }
            }
            Button(store.isFavorite(key: item.favoriteKey) ? "Remove Favorite" : "Add Favorite") {
                store.toggleFavorite(key: item.favoriteKey)
            }
            Button("Controller Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private var quickMenu: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Boreal Quick Menu", systemImage: "gamecontroller.fill").font(.title2.bold())
            if let app = selectedApplication {
                quickAction("Resume / Play", symbol: "play.fill", disabled: app.status == .running) { store.toggleRunning(app.id) }
                quickAction("Stop Game", symbol: "stop.fill", disabled: app.status != .running) { store.toggleRunning(app.id) }
                quickAction("Open Performance Overlay", symbol: "gauge.with.dots.needle.67percent", disabled: app.status != .running) { GameOverlayController.shared.toggleVisibility() }
            } else {
                Text("Select a running game to manage it here.").foregroundStyle(.secondary)
            }
            Button("Close") { showsQuickMenu = false }.buttonStyle(.borderedProminent)
        }
        .padding(28).frame(width: 360)
    }

    private func quickAction(_ title: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading) }
            .buttonStyle(.bordered).controlSize(.large).disabled(disabled)
    }

    private func install(_ game: StoreLibraryGame) {
        switch game.provider {
        case .steam: store.installSteamWindowsGame(game)
        case .epic, .gog: store.installStoreGame(game)
        }
    }
}

private struct ConsoleControlHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(key).font(.caption.bold()).foregroundStyle(.black)
                .frame(minWidth: 24, minHeight: 24).background(.white, in: Circle())
            Text(label).foregroundStyle(.secondary)
        }
        .padding(.trailing, 8)
    }
}

private enum ConsoleSection: String, CaseIterable, Identifiable {
    case home, library, installed, recent, favorites, downloads, activity, settings
    var id: String { rawValue }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var title: String { rawValue.capitalized }
}

private struct ConsoleGameDetailView: View {
    let item: LibraryItem?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Back to \(item?.name ?? "Library")", systemImage: "chevron.left", action: close)
                .buttonStyle(.bordered).controlSize(.large)
            if let item {
                switch item.kind {
                case .application(let application):
                    AppDetailView(app: application, didRemove: close)
                case .storeGame(let game):
                    StoreGameDetailView(game: game)
                }
            } else {
                ContentUnavailableView("Game Not Found", systemImage: "questionmark.app")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConsoleNavButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: selected ? .bold : .semibold, design: .rounded))
            .foregroundStyle(selected ? .white : .secondary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(selected ? Color.cyan.opacity(0.2) : .clear, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.cyan.opacity(0.65) : .clear, lineWidth: 1))
    }
}

private struct ConsoleHomeHero: View {
    let item: LibraryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                heroArtwork
                LinearGradient(
                    colors: [.clear, .black.opacity(0.28), .black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                HStack(alignment: .bottom, spacing: 30) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(item.running ? "PLAYING NOW" : "CONTINUE PLAYING", systemImage: item.running ? "dot.radiowaves.left.and.right" : "play.circle.fill")
                            .font(.caption.bold()).tracking(1.3).foregroundStyle(item.running ? .green : .cyan)
                        Text(item.name)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .lineLimit(2)
                        if let summary {
                            Text(summary).font(.title3).foregroundStyle(.white.opacity(0.78)).lineLimit(2)
                                .frame(maxWidth: 820, alignment: .leading)
                        }
                        HStack(spacing: 14) {
                            Label(item.running ? "Running" : (item.readyToPlay ? "Play" : "View game"), systemImage: item.running ? "waveform" : "play.fill")
                                .font(.headline).padding(.horizontal, 20).padding(.vertical, 12)
                                .background(.cyan, in: Capsule()).foregroundStyle(.black)
                            Label(item.source.title, systemImage: item.kind.consoleSymbol).foregroundStyle(.white.opacity(0.75))
                            Label(item.compatibility.rawValue, systemImage: item.compatibility.symbol).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    Spacer()
                    if let game = storeGame, let rating = game.storeRating {
                        StoreRatingBadge(rating: rating)
                            .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(38)
            }
            .frame(maxWidth: .infinity, minHeight: 330, maxHeight: 380)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 18)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var heroArtwork: some View {
        if let game = storeGame,
           let value = game.backgroundImageURL ?? game.headerImageURL ?? game.portraitImageURL,
           let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { heroPlaceholder }
            }
        } else {
            heroPlaceholder
        }
    }

    private var heroPlaceholder: some View {
        LinearGradient(colors: [.indigo.opacity(0.82), .cyan.opacity(0.28), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .trailing) {
                Image(systemName: item.kind.consoleSymbol).font(.system(size: 170, weight: .thin)).foregroundStyle(.white.opacity(0.1)).padding(70)
            }
    }

    private var storeGame: StoreLibraryGame? {
        if case .storeGame(let game) = item.kind { return game }
        return nil
    }

    private var summary: String? {
        guard let text = storeGame?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

private struct ConsoleGameCard: View {
    let item: LibraryItem
    let focused: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    switch item.kind {
                    case .application(let application):
                        AppIconView(symbol: application.iconSymbol, size: 58)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.08))
                    case .storeGame(let game):
                        GameArtworkView(game: game, width: 288, height: 172)
                    }
                }
                .frame(width: 288, height: 172)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(item.name).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1)
                HStack {
                    Label(item.statusText, systemImage: item.running ? "play.circle.fill" : "circle.fill")
                        .foregroundStyle(item.running ? .green : .secondary)
                    Spacer()
                    Image(systemName: item.source.symbol).foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
            }
            .padding(14).background(.white.opacity(focused ? 0.16 : 0.075), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(focused ? .cyan : .white.opacity(0.07), lineWidth: focused ? 3 : 1))
            .shadow(color: focused ? .cyan.opacity(0.22) : .black.opacity(0.2), radius: focused ? 18 : 8, y: 8)
            .scaleEffect(focused ? 1.035 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(.plain)
        .frame(width: 316, height: 256)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension LibraryItem.Kind {
    var consoleSymbol: String {
        switch self {
        case .application: "app.dashed"
        case .storeGame: "gamecontroller.fill"
        }
    }
}
