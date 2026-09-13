import AppKit
import SwiftUI

struct GameDiscoveryBanner: View {
    let candidateCount: Int
    let openAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Found \(candidateCount) new \(candidateCount == 1 ? "game" : "games")")
                    .font(.headline)
                Text("Review detected installations before adding them to Boreal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review", action: openAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

struct GameDiscoverySheet: View {
    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Label("Find installed games", systemImage: "magnifyingglass")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close")
            }
            .padding(.bottom, 8)

            Text("Boreal checks store manifests first, then trusted Windows metadata and only the folders configured for discovery.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            content

            Divider().padding(.top, 12)
            HStack {
                if let date = store.gameDiscoveryLastScannedAt {
                    Text("Last scan \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .scanning = store.gameDiscoveryState {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").foregroundStyle(.secondary)
                }
                Button("Scan now", systemImage: "arrow.clockwise") {
                    store.scanForInstalledGames(force: true)
                }
                .disabled(isScanning)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 760, height: 600)
        .task {
            if case .idle = store.gameDiscoveryState {
                store.scanForInstalledGames(force: false)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.gameDiscoveryState {
        case .idle, .scanning where store.gameDiscoveryCandidates.isEmpty:
            VStack(spacing: 12) {
                ProgressView()
                Text("Looking for installed games…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Discovery failed", systemImage: "exclamationmark.triangle", description: Text(message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded where store.gameDiscoveryCandidates.isEmpty:
            ContentUnavailableView(
                "No new games found",
                systemImage: "checkmark.circle",
                description: Text("Add a game folder in Settings → General → Game discovery, or choose Scan now after installing a game.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            List(store.gameDiscoveryCandidates) { candidate in
                GameDiscoveryCandidateRow(candidate: candidate) {
                    store.importDiscoveredGame(candidate)
                }
                .listRowSeparator(.visible)
            }
            .listStyle(.inset)
        }
    }

    private var isScanning: Bool {
        if case .scanning = store.gameDiscoveryState { return true }
        return false
    }
}

private struct GameDiscoveryCandidateRow: View {
    let candidate: GameDiscoveryCandidate
    let importAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: candidate.storeReference?.provider.symbol ?? candidate.source.symbol)
                .font(.title3)
                .foregroundStyle(candidate.isAutomaticallyImportable ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(candidate.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(candidate.confidenceTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(candidate.isAutomaticallyImportable ? .green : .secondary)
                }
                Text(candidate.sourceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(candidate.installPath.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !candidate.reasons.isEmpty {
                    Text(candidate.reasons.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !candidate.penalties.isEmpty {
                    Text("Caution: \(candidate.penalties.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                Text("\(candidate.score)/100")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(candidate.isAutomaticallyImportable ? .green : .secondary)
                Button(candidate.storeReference?.provider == .steam ? "Refresh Steam" : "Add", action: importAction)
                    .buttonStyle(.bordered)
                Button("Show", systemImage: "folder") {
                    NSWorkspace.shared.open(candidate.installPath)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(candidate.name), \(candidate.confidenceTitle), score \(candidate.score) out of 100")
    }
}

struct GameDiscoverySettingsCard: View {
    @Environment(BorealStore.self) private var store
    @State private var configuration = GameDiscoveryConfiguration.load()

    var body: some View {
        SettingsCard(
            "Game discovery",
            subtitle: "Find installed games from trusted manifests, Windows metadata and selected folders.",
            symbol: "magnifyingglass"
        ) {
            Toggle("Automatic discovery", isOn: Binding(
                get: { !configuration.enabledSources.isEmpty },
                set: { enabled in
                    configuration.enabledSources = enabled ? Set(GameDiscoverySource.allCases) : []
                    saveConfiguration()
                }
            ))

            Divider()
            Text("Search in")
                .font(.callout.weight(.medium))
            ForEach(GameDiscoverySource.allCases) { source in
                Toggle(isOn: Binding(
                    get: { configuration.enabledSources.contains(source) },
                    set: { enabled in
                        if enabled { configuration.enabledSources.insert(source) }
                        else { configuration.enabledSources.remove(source) }
                        saveConfiguration()
                    }
                )) {
                    Label(source.title, systemImage: source.symbol)
                }
                .toggleStyle(.checkbox)
            }

            Divider()
            SettingsRow("Automatic import") {
                Picker("Automatic import", selection: Binding(
                    get: { configuration.automaticImportMode },
                    set: { configuration.automaticImportMode = $0; saveConfiguration() }
                )) {
                    ForEach(GameDiscoveryAutomaticImportMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
            }

            if !configuration.customRoots.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Additional folders")
                        .font(.callout.weight(.medium))
                    ForEach(configuration.customRoots, id: \.self) { root in
                        HStack {
                            Text(root.path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") {
                                store.removeGameDiscoveryRoot(root)
                                configuration = store.gameDiscoveryConfiguration
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            HStack {
                Button("Add folder…", systemImage: "folder.badge.plus") { addFolder() }
                Spacer()
                Button("Scan now", systemImage: "magnifyingglass") { store.scanForInstalledGames(force: true) }
            }
            .padding(.top, 4)
        }
        .onAppear { configuration = store.gameDiscoveryConfiguration }
    }

    private func saveConfiguration() {
        configuration.save()
        store.updateGameDiscoveryConfiguration(configuration)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to search"
        panel.prompt = "Add"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.addGameDiscoveryRoot(url)
            configuration = store.gameDiscoveryConfiguration
        }
    }
}
