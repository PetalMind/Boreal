import AppKit
import SwiftUI

/// A deliberately separate presentation layer for controller-first use. The
/// desktop split view remains unchanged; this view owns its own hierarchy and
/// keeps the focused item stable while the user visits a game.
struct ConsoleModeView: View {
    @Environment(BorealStore.self) private var store
    @State private var section = ConsoleSection.home
    @State private var focusedID: LibraryItem.ID?
    @State private var focusedRail = 0
    @State private var focusedIndex = 0
    @State private var focusedControl = 0
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
                ScrollViewReader { verticalProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        if selectedItem == nil {
                            Text(section.title)
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .tracking(-1.1)
                        }
                        if selectedItem != nil {
                            consoleGameDetail
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
                .onChange(of: focusAnchor) { _, anchor in
                    guard let anchor else { return }
                    withAnimation(.easeOut(duration: 0.18)) { verticalProxy.scrollTo(anchor, anchor: .center) }
                }
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
            resetFocus()
        }
        .onAppear { resetFocus() }
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
            Button {
                consoleModeEnabled.toggle()
            } label: {
                Image(systemName: "gamecontroller.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Turn off console mode")
            .accessibilityLabel("Turn off console mode")
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
                focusedRail = 0
                focusedIndex = 0
                focusedID = featured.id
                selectedItem = featured.id
            }
            .overlay(consoleFocusOutline(focusedRail == 0))
            .id("rail-0")
        }
        let recent = Array(items.prefix(8))
        if !recent.isEmpty { gameRail(title: "Recently Added", values: recent, rail: 1) }
        let favorites = items.filter { store.favoriteKeys.contains($0.favoriteKey) }.prefix(8).map { $0 }
        if !favorites.isEmpty { gameRail(title: "Favorites", values: favorites, rail: 2) }
        let ready = items.filter(\.readyToPlay).prefix(8).map { $0 }
        if !ready.isEmpty { gameRail(title: "Installed & Ready", values: ready, rail: 3) }
        let attention = items.filter(\.needsAttention)
        if !attention.isEmpty { gameRail(title: "Needs Attention", values: attention, rail: 4) }
        downloadsSummary
    }

    private func gameRail(title: String, values: [LibraryItem], rail: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(values.count.formatted()).font(.callout.bold().monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(.white.opacity(0.08), in: Capsule())
            }
            if values.isEmpty {
                Text("Nothing here yet.").foregroundStyle(.secondary).font(.title3)
            } else {
                ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 22) {
                        ForEach(values) { item in
                            ConsoleGameCard(item: item, focused: focusedRail == rail && focusedID == item.id) {
                                focusedRail = rail
                                focusedIndex = values.firstIndex(where: { $0.id == item.id }) ?? 0
                                focusedID = item.id
                                selectedItem = item.id
                            }
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 8)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, -8, for: .scrollContent)
                .onChange(of: focusedID) { _, id in
                    guard focusedRail == rail, let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) }
                }
                }
            }
        }
        .padding(.top, 6)
        .id("rail-\(rail)")
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
                ForEach(Array(store.activeStoreGameOperations.enumerated()), id: \.element.game.id) { index, operation in
                    Button {
                        toggleDownload(operation)
                    } label: { HStack(spacing: 18) {
                        Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(operation.game.name).font(.title3.weight(.semibold))
                            Text(operation.state.progress.map { progressText($0) } ?? "Preparing")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(operation.state.isCancellable ? "Pause" : "Resume").foregroundStyle(.cyan)
                    }}
                    .buttonStyle(.plain)
                    .padding(18).background(.white.opacity(focusedControl == index ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(consoleFocusOutline(focusedControl == index))
                    .id("control-\(index)")
                }
            }
        }
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recent activity").font(.title2.bold())
            ForEach(Array(items.filter { $0.lastUsed != nil }.prefix(8).enumerated()), id: \.element.id) { index, item in
                Button { focusedID = item.id; selectedItem = item.id } label: { HStack {
                    Image(systemName: item.running ? "play.circle.fill" : "clock").foregroundStyle(item.running ? .green : .secondary)
                    Text(item.name).font(.title3.weight(.medium))
                    Spacer()
                    Text(item.lastUsed ?? .distantPast, style: .relative).foregroundStyle(.secondary)
                }}
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.white.opacity(focusedControl == index ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 12))
                .overlay(consoleFocusOutline(focusedControl == index))
                .id("control-\(index)")
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Fullscreen settings").font(.title2.bold())
            Toggle("Keep TV mode enabled", isOn: $consoleModeEnabled)
                .font(.title3).toggleStyle(.switch).padding(18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(consoleFocusOutline(focusedControl == 0))
                .id("control-0")
            Toggle("Ask to enter when a controller connects", isOn: $consoleModeAutoEnter)
                .font(.title3).toggleStyle(.switch).padding(18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(consoleFocusOutline(focusedControl == 1))
                .id("control-1")
            Toggle("Return after a game exits while a controller is connected", isOn: $consoleModeReturnAfterGame)
                .font(.title3).toggleStyle(.switch).padding(18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(consoleFocusOutline(focusedControl == 2))
                .id("control-2")
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

    private var focusAnchor: String? {
        if selectedItem != nil { return "console-detail" }
        switch section {
        case .home, .library, .installed, .recent, .favorites: return "rail-\(focusedRail)"
        case .downloads, .activity, .settings: return "control-\(focusedControl)"
        }
    }

    private var homeRails: [[LibraryItem]] {
        let featured = (items.first(where: { $0.lastUsed != nil }) ?? items.first).map { [$0] } ?? []
        return [
            featured,
            Array(items.prefix(8)),
            items.filter { store.favoriteKeys.contains($0.favoriteKey) }.prefix(8).map { $0 },
            items.filter(\.readyToPlay).prefix(8).map { $0 },
            items.filter(\.needsAttention)
        ]
    }

    private var currentRailItems: [LibraryItem] {
        if section == .home { return homeRails[safe: focusedRail] ?? [] }
        return items
    }

    private var consoleGameDetail: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let item = selectedItem.flatMap({ id in items.first { $0.id == id } }) {
                HStack(alignment: .top, spacing: 28) {
                    switch item.kind {
                    case .application(let application):
                        AppIconView(symbol: application.iconSymbol, size: 96)
                            .frame(width: 240, height: 160)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    case .storeGame(let game):
                        GameArtworkView(game: game, width: 300, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.name).font(.system(size: 42, weight: .bold, design: .rounded))
                        Label(item.statusText, systemImage: item.running ? "play.circle.fill" : "gamecontroller.fill")
                            .font(.title3).foregroundStyle(item.running ? .green : .secondary)
                        Text("Choose an action with the D-pad and press A.").foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 12) {
                    detailActionRow(index: 0, title: primaryDetailTitle(item), symbol: primaryDetailSymbol(item)) {
                        activateSelectedGame()
                    }
                    detailActionRow(index: 1, title: store.isFavorite(key: item.favoriteKey) ? "Remove from Favorites" : "Add to Favorites", symbol: "heart.fill") {
                        store.toggleFavorite(key: item.favoriteKey)
                    }
                    if item.running {
                        detailActionRow(index: 2, title: "Performance Overlay", symbol: "gauge.with.dots.needle.67percent") {
                            GameOverlayController.shared.toggleVisibility()
                        }
                    }
                    detailActionRow(index: item.running ? 3 : 2, title: "Back to Library", symbol: "chevron.left") {
                        selectedItem = nil; focusedControl = 0
                    }
                }
            } else {
                ContentUnavailableView("Game Not Found", systemImage: "questionmark.app")
            }
        }
        .id("console-detail")
    }

    private func detailActionRow(index: Int, title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }
        .buttonStyle(.plain)
        .background(.white.opacity(focusedControl == index ? 0.16 : 0.075), in: RoundedRectangle(cornerRadius: 16))
        .overlay(consoleFocusOutline(focusedControl == index))
    }

    private func consoleFocusOutline(_ visible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16).stroke(visible ? .cyan : .clear, lineWidth: 3)
    }

    private func primaryDetailTitle(_ item: LibraryItem) -> String {
        if item.running { return "Stop Game" }
        return item.readyToPlay ? "Play" : "Install / Prepare"
    }

    private func primaryDetailSymbol(_ item: LibraryItem) -> String {
        item.running ? "stop.fill" : (item.readyToPlay ? "play.fill" : "arrow.down.circle.fill")
    }

    private func toggleDownload(_ operation: (game: StoreLibraryGame, state: StoreGameOperationState)) {
        if operation.state.isCancellable { store.cancelStoreGameOperation(operation.game) }
        else { store.resumeStoreGameOperation(operation.game) }
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
        if showsOnboarding {
            if input == .buttonA {
                UserDefaults.standard.set(true, forKey: "consoleModeOnboardingShown")
                showsOnboarding = false
            } else if input == .buttonB {
                showsOnboarding = false
            }
            return
        }
        if showsQuickMenu {
            if input == .buttonB || input == .menu { showsQuickMenu = false }
            else if input == .buttonA, let app = selectedApplication {
                if app.status == .running { GameOverlayController.shared.toggleVisibility() }
                else { store.toggleRunning(app.id) }
                showsQuickMenu = false
            }
            return
        }
        if showsGameMenu {
            if input == .buttonB || input == .buttonY { showsGameMenu = false }
            else if input == .buttonA {
                activateSelectedGame()
                showsGameMenu = false
            } else if input == .buttonX, let item = focusedItem {
                store.toggleFavorite(key: item.favoriteKey)
                showsGameMenu = false
            }
            return
        }
        switch input {
        case .leftShoulder: moveSection(by: -1)
        case .rightShoulder: moveSection(by: 1)
        case .dpadLeft, .leftStickLeft: moveHorizontal(by: -1)
        case .dpadRight, .leftStickRight: moveHorizontal(by: 1)
        case .dpadUp, .leftStickUp: moveVertical(by: -1)
        case .dpadDown, .leftStickDown: moveVertical(by: 1)
        case .buttonA: activateFocusedControl()
        case .buttonB:
            if selectedItem != nil { selectedItem = nil }
            else { exit() }
        case .buttonX:
            if selectedItem != nil || [.home, .library, .installed, .recent, .favorites].contains(section),
               let item = focusedItem {
                store.toggleFavorite(key: item.favoriteKey)
            }
        case .buttonY:
            if (selectedItem != nil || [.home, .library, .installed, .recent, .favorites].contains(section)),
               focusedItem != nil {
                showsGameMenu = true
            }
        case .menu: showsQuickMenu = true
        default: break
        }
    }

    private func moveSection(by offset: Int) {
        guard selectedItem == nil else { return }
        section = ConsoleSection.allCases[min(max(0, section.index + offset), ConsoleSection.allCases.count - 1)]
    }

    private func moveHorizontal(by offset: Int) {
        if selectedItem != nil {
            moveDetailFocus(by: offset)
            return
        }
        switch section {
        case .home, .library, .installed, .recent, .favorites:
            let values = currentRailItems
            guard !values.isEmpty else { return }
            focusedIndex = min(max(0, focusedIndex + offset), values.count - 1)
            focusedID = values[focusedIndex].id
        case .settings:
            activateSetting()
        case .downloads, .activity:
            break
        }
    }

    private func moveVertical(by offset: Int) {
        if selectedItem != nil {
            moveDetailFocus(by: offset)
            return
        }
        switch section {
        case .home:
            let available = homeRails.indices.filter { !homeRails[$0].isEmpty }
            guard let position = available.firstIndex(of: focusedRail) else { return }
            focusedRail = available[min(max(0, position + offset), available.count - 1)]
            let values = currentRailItems
            focusedIndex = min(focusedIndex, max(0, values.count - 1))
            focusedID = values[safe: focusedIndex]?.id
        case .library, .installed, .recent, .favorites:
            break
        case .downloads:
            let count = store.activeStoreGameOperations.count
            if count > 0 { focusedControl = min(max(0, focusedControl + offset), count - 1) }
        case .activity:
            let count = items.filter { $0.lastUsed != nil }.prefix(8).count
            if count > 0 { focusedControl = min(max(0, focusedControl + offset), count - 1) }
        case .settings:
            focusedControl = min(max(0, focusedControl + offset), 2)
        }
    }

    private func activateFocusedControl() {
        if selectedItem != nil {
            activateDetailControl()
            return
        }
        switch section {
        case .home, .library, .installed, .recent, .favorites:
            selectedItem = focusedID
            focusedControl = 0
        case .downloads:
            guard let operation = store.activeStoreGameOperations[safe: focusedControl] else { return }
            toggleDownload(operation)
        case .activity:
            let values = Array(items.filter { $0.lastUsed != nil }.prefix(8))
            guard let item = values[safe: focusedControl] else { return }
            focusedID = item.id; selectedItem = item.id; focusedControl = 0
        case .settings:
            activateSetting()
        }
    }

    private func activateSetting() {
        switch focusedControl {
        case 0: consoleModeEnabled.toggle()
        case 1: consoleModeAutoEnter.toggle()
        case 2: consoleModeReturnAfterGame.toggle()
        default: break
        }
    }

    private func moveDetailFocus(by offset: Int) {
        let maximum = focusedItem?.running == true ? 3 : 2
        focusedControl = min(max(0, focusedControl + offset), maximum)
    }

    private func activateDetailControl() {
        guard let item = focusedItem else { return }
        switch focusedControl {
        case 0: activateSelectedGame()
        case 1: store.toggleFavorite(key: item.favoriteKey)
        case 2 where item.running: GameOverlayController.shared.toggleVisibility()
        default: selectedItem = nil; focusedControl = 0
        }
    }

    private func resetFocus() {
        focusedRail = 0
        focusedIndex = 0
        focusedControl = 0
        if section == .home {
            let first = homeRails.indices.first { !homeRails[$0].isEmpty } ?? 0
            focusedRail = first
            focusedID = homeRails[safe: first]?.first?.id
        } else {
            focusedID = items.first?.id
        }
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
