import AppKit
import AVKit
import SwiftUI

struct StoreGameDetailView: View {
    @Environment(BorealStore.self) private var store
    let game: StoreLibraryGame
    @State private var confirmsStoreInstall = false
    @State private var selectedVideo: StoreVideo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero
                HStack(alignment: .top, spacing: 26) {
                    GameArtworkView(game: game, width: 190, height: 266)
                    VStack(alignment: .leading, spacing: 12) {
                        Label(game.provider.rawValue, systemImage: game.provider.symbol)
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(game.name).font(.largeTitle).fontWeight(.bold)
                        if let developer = game.developer {
                            Text(developer).font(.title3).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            if game.provider == .steam {
                                if let app = linkedApplication {
                                    Button(app.status == .running ? "Stop" : "Play Windows Version", systemImage: app.status == .running ? "stop.fill" : "play.fill") {
                                        store.toggleRunning(app.id)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                    .disabled(app.status.isBusy || app.status == .unavailable)
                                } else if game.supportsNativeMacOS == false, game.supportsWindows == true, storeOperation == nil {
                                    Button("Install Windows Version", systemImage: "arrow.down.circle.fill") {
                                        confirmsStoreInstall = true
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                } else {
                                    Button(game.isInstalled ? "Play Native macOS Version" : "Open in Steam", systemImage: game.isInstalled ? "play.fill" : "arrow.up.right.square") {
                                        openSteam()
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                }
                                Button("Store Page", systemImage: "storefront") { openStorePage() }
                                    .controlSize(.large)
                            } else if game.isInstalled {
                                if let app = linkedApplication {
                                    Button(app.status == .running ? "Stop" : "Play in Boreal", systemImage: app.status == .running ? "stop.fill" : "play.fill") {
                                        store.toggleRunning(app.id)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                    .disabled(app.status.isBusy || app.status == .unavailable)
                                } else if storeOperation == nil {
                                    Button("Prepare to Play", systemImage: "wand.and.stars") {
                                        store.prepareStoreGame(game)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                }
                                if let installPath = game.installPath {
                                    Button("Show Game Files", systemImage: "folder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installPath)])
                                    }
                                    .controlSize(.large)
                                }
                            } else if storeOperation == nil {
                                Button("Install Windows Version", systemImage: "arrow.down.circle.fill") {
                                    confirmsStoreInstall = true
                                }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                            }
                        }
                        .padding(.top, 4)
                        if let progress = storeOperation?.progress {
                            operationProgress(progress)
                        } else if case .awaitingProvider(let message) = storeOperation {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(message, systemImage: "info.circle.fill")
                                    .foregroundStyle(.secondary)
                                Button("Dismiss Status") { store.clearStoreGameOperation(for: game) }
                                    .buttonStyle(.plain)
                            }
                        } else if case .failed(let message) = storeOperation {
                            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            if game.provider == .steam {
                                Button("Try Windows Installation Again", systemImage: "arrow.clockwise") {
                                    store.clearStoreGameOperation(for: game)
                                    confirmsStoreInstall = true
                                }
                            } else if game.isInstalled {
                                Button("Try Preparation Again", systemImage: "arrow.clockwise") {
                                    store.clearStoreGameOperation(for: game)
                                    store.prepareStoreGame(game)
                                }
                            } else {
                                Button("Try Installation Again", systemImage: "arrow.clockwise") {
                                    store.clearStoreGameOperation(for: game)
                                    confirmsStoreInstall = true
                                }
                            }
                        }
                        if linkedApplication != nil {
                            Label("Windows version managed by Boreal and \(game.provider.rawValue)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if game.isInstalled {
                            Label("Installed from \(game.provider.rawValue)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Label("Available in your \(game.provider.rawValue) Library", systemImage: "cloud.fill").foregroundStyle(.secondary)
                        }
                        HStack(spacing: 16) {
                            StorePlatformBadge(game: game)
                            StoreRatingBadge(rating: game.storeRating)
                            if let compatibility = game.compatibility {
                                MacCompatibilityBadge(rating: compatibility.tier.rating)
                            }
                        }
                    }
                    Spacer()
                }

                if let summary = game.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About").font(.title2).fontWeight(.semibold)
                        Text(summary).font(.body).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }

                if game.provider == .steam { compatibilitySection }

                mediaSection

                Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 18) {
                    GridRow {
                        metric("Playtime", value: playtime, symbol: "clock")
                        metric("Last played", value: game.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "Never", symbol: "calendar")
                    }
                    GridRow {
                        metric("Source", value: game.provider.rawValue, symbol: "person.crop.circle.badge.checkmark")
                        metric("Store game ID", value: game.externalID, symbol: "number")
                    }
                }

                if let installPath = game.installPath {
                    Button("Show Game Files", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installPath)])
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: 960, alignment: .leading)
        }
        .confirmationDialog("Install \(game.name)?", isPresented: $confirmsStoreInstall) {
            Button("Download and Install") {
                if game.provider == .steam { store.installSteamWindowsGame(game) }
                else { store.installStoreGame(game) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if game.provider == .steam {
                Text("Boreal will install Valve’s official Steam for Windows client in an isolated environment and open this game’s installation. Sign in inside Steam; Boreal never receives your password or Steam Guard code.")
            } else {
                Text("Boreal will download the Windows build from \(game.provider.rawValue) using its verified support component. Game downloads can be large and continue until the operation finishes or the app is closed.")
            }
        }
        .sheet(item: $selectedVideo) { video in
            StoreVideoPlayerView(video: video)
        }
    }

    @ViewBuilder private var hero: some View {
        if let value = game.backgroundImageURL ?? game.headerImageURL, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.clear)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.16))
            }
        }
    }

    private var playtime: String {
        guard game.playtimeMinutes > 0 else { return "Not played" }
        if game.playtimeMinutes < 60 { return "\(game.playtimeMinutes) min" }
        return String(format: "%.1f hours", Double(game.playtimeMinutes) / 60)
    }

    private var storeOperation: StoreGameOperationState? {
        store.storeGameOperation(for: game)
    }

    private func operationProgress(_ progress: StoreGameOperationProgress) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                if let fraction = progress.clampedFraction {
                    ProgressView(value: fraction).frame(maxWidth: 270)
                    Text("\(Int(fraction * 100))%").monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(progress.message).foregroundStyle(.secondary)
            }
            if storeOperation?.isCancellable == true {
                Button("Cancel Operation", systemImage: "xmark.circle", role: .cancel) {
                    store.cancelStoreGameOperation(game)
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.message)
    }

    @ViewBuilder private var mediaSection: some View {
        let screenshots = game.screenshotURLs ?? []
        let videos = game.videos ?? []
        if !screenshots.isEmpty || !videos.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Media").font(.title2).fontWeight(.semibold)
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(Array(screenshots.enumerated()), id: \.offset) { _, value in
                            if let url = URL(string: value) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() }
                                    else { Rectangle().fill(.background.secondary) }
                                }
                                .frame(width: 310, height: 174)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                        }
                        ForEach(videos) { video in
                            Button { selectedVideo = video } label: {
                                ZStack {
                                    if let thumbnail = video.thumbnailURL, let url = URL(string: thumbnail) {
                                        AsyncImage(url: url) { phase in
                                            if let image = phase.image { image.resizable().scaledToFill() }
                                            else { Rectangle().fill(.background.secondary) }
                                        }
                                    }
                                    Color.black.opacity(0.25)
                                    Image(systemName: "play.circle.fill").font(.system(size: 46)).foregroundStyle(.white)
                                }
                                .frame(width: 310, height: 174)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(video.name)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var linkedApplication: WindowsApplication? { store.linkedApplication(for: game) }

    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Windows Compatibility").font(.title2).fontWeight(.semibold)
            if let profile = game.compatibility {
                HStack(alignment: .top, spacing: 18) {
                    CommunityCompatibilityBadge(profile: profile)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Community reports from \(profile.source.rawValue)")
                            .fontWeight(.medium)
                        Text(compatibilitySummary(profile))
                            .font(.callout).foregroundStyle(.secondary)
                        Text("This is Proton/Wine community evidence, not a guarantee for Boreal on macOS.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No compatibility reports",
                    systemImage: "questionmark.circle",
                    description: Text("No ProtonDB summary was available for this Steam App ID.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
            HStack {
                Button("Open ProtonDB", systemImage: "safari") { openProtonDB() }
                Button("Browse WineHQ AppDB", systemImage: "magnifyingglass") { openWineAppDB() }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.14)) }
    }

    private func compatibilitySummary(_ profile: CommunityCompatibility) -> String {
        var parts = ["\(profile.reportCount.formatted()) reports"]
        if let confidence = profile.confidence { parts.append("\(confidence.capitalized) confidence") }
        if let trending = profile.trendingTier, trending != profile.tier { parts.append("Trending: \(trending.title)") }
        return parts.joined(separator: " · ")
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openSteam() {
        let action = game.isInstalled ? "rungameid" : "store"
        if let url = URL(string: "steam://\(action)/\(game.externalID)") { NSWorkspace.shared.open(url) }
    }

    private func openStorePage() {
        if let url = URL(string: "https://store.steampowered.com/app/\(game.externalID)") { NSWorkspace.shared.open(url) }
    }

    private func openProtonDB() {
        if let url = URL(string: "https://www.protondb.com/app/\(game.externalID)") { NSWorkspace.shared.open(url) }
    }

    private func openWineAppDB() {
        var components = URLComponents(string: "https://appdb.winehq.org/objectManager.php")
        components?.queryItems = [
            URLQueryItem(name: "sClass", value: "application"),
            URLQueryItem(name: "iAction", value: "browse"),
            URLQueryItem(name: "iItemsPerPage", value: "25")
        ]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }
}

private struct StoreVideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let video: StoreVideo
    @State private var player: AVPlayer

    init(video: StoreVideo) {
        self.video = video
        _player = State(initialValue: AVPlayer())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(video.name).font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            VideoPlayer(player: player)
                .frame(minWidth: 760, minHeight: 430)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.16)) }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .onAppear {
            guard let url = URL(string: video.videoURL) else { return }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }
        .onDisappear { player.pause() }
    }
}
