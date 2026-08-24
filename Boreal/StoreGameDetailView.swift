import AppKit
import SwiftUI

struct StoreGameDetailView: View {
    @Environment(BorealStore.self) private var store
    let game: StoreLibraryGame
    @State private var confirmsEpicInstall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero
                HStack(alignment: .top, spacing: 26) {
                    GameArtworkView(game: game, width: 190, height: 266)
                    VStack(alignment: .leading, spacing: 12) {
                        Label(game.provider.rawValue, systemImage: "gamecontroller.fill")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(game.name).font(.largeTitle).fontWeight(.bold)
                        if let developer = game.developer {
                            Text(developer).font(.title3).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            if game.provider == .steam {
                                Button(game.isInstalled ? "Play in Steam" : "Open in Steam", systemImage: game.isInstalled ? "play.fill" : "arrow.up.right.square") {
                                    openSteam()
                                }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                Button("Store Page", systemImage: "storefront") { openStorePage() }
                                    .controlSize(.large)
                            } else if game.isInstalled {
                                if let app = linkedApplication {
                                    Button(app.status == .running ? "Stop" : "Play in Boreal", systemImage: app.status == .running ? "stop.fill" : "play.fill") {
                                        store.toggleRunning(app.id)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                    .disabled(app.status.isBusy || app.status == .unavailable)
                                } else if epicOperation == nil {
                                    Button("Prepare to Play", systemImage: "wand.and.stars") {
                                        store.prepareEpicGame(game)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                }
                                if let installPath = game.installPath {
                                    Button("Show Game Files", systemImage: "folder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installPath)])
                                    }
                                    .controlSize(.large)
                                }
                            } else if epicOperation == nil {
                                Button("Install Windows Version", systemImage: "arrow.down.circle.fill") {
                                    confirmsEpicInstall = true
                                }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                            }
                        }
                        .padding(.top, 4)
                        if case .installing = epicOperation {
                            HStack(spacing: 9) {
                                ProgressView().controlSize(.small)
                                Text("Downloading and installing through Epic…")
                            }
                            .foregroundStyle(.secondary)
                        } else if case .preparingEnvironment = epicOperation {
                            HStack(spacing: 9) {
                                ProgressView().controlSize(.small)
                                Text("Creating and validating an isolated Windows environment…")
                            }
                            .foregroundStyle(.secondary)
                        } else if case .failed(let message) = epicOperation {
                            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            if game.isInstalled {
                                Button("Try Preparation Again", systemImage: "arrow.clockwise") {
                                    store.clearStoreGameOperation(for: game.externalID)
                                    store.prepareEpicGame(game)
                                }
                            } else {
                                Button("Try Installation Again", systemImage: "arrow.clockwise") {
                                    store.clearStoreGameOperation(for: game.externalID)
                                    confirmsEpicInstall = true
                                }
                            }
                        }
                        if game.isInstalled {
                            Label("Installed from \(game.provider.rawValue)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Label("Available in your \(game.provider.rawValue) Library", systemImage: "cloud.fill").foregroundStyle(.secondary)
                        }
                        if game.provider == .steam { CommunityCompatibilityBadge(profile: game.compatibility) }
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

                Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 18) {
                    GridRow {
                        metric("Playtime", value: playtime, symbol: "clock")
                        metric("Last played", value: game.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "Never", symbol: "calendar")
                    }
                    GridRow {
                        metric("Source", value: game.provider.rawValue, symbol: "person.crop.circle.badge.checkmark")
                        metric("Steam App ID", value: game.externalID, symbol: "number")
                    }
                }

                if let installPath = game.installPath {
                    Button("Show Steam Files", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installPath)])
                    }
                }
            }
            .padding(36)
            .frame(maxWidth: 960, alignment: .leading)
        }
        .confirmationDialog("Install \(game.name)?", isPresented: $confirmsEpicInstall) {
            Button("Download and Install") { store.installEpicGame(game) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Boreal will download the Windows build from Epic through Legendary. Game downloads can be large and continue until the operation finishes or the app is closed.")
        }
    }

    @ViewBuilder private var hero: some View {
        if let value = game.headerImageURL, let url = URL(string: value) {
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

    private var epicOperation: StoreGameOperationState? {
        guard game.provider == .epic else { return nil }
        return store.storeGameOperations[game.externalID]
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
