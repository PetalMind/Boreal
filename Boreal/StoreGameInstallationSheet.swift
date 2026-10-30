import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StoreGameInstallationSheet: View {
    private enum InstallationChoice: Hashable {
        case install
        case existing
    }

    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let game: StoreLibraryGame
    let completion: (URL?) -> Void
    @State private var destination: URL
    @State private var choice: InstallationChoice = .install
    @State private var hasStartedInstallation = false
    @State private var showsProgressDetails = false

    init(game: StoreLibraryGame, defaultDestination: URL, completion: @escaping (URL?) -> Void) {
        self.game = game
        self.completion = completion
        _destination = State(initialValue: defaultDestination)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if hasStartedInstallation, let operation = store.storeGameOperation(for: game) {
                progressContent(operation)
            } else {
                configurationContent
            }
        }
        .padding(28)
        .frame(width: 650)
        .background(
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.13), Color(red: 0.055, green: 0.06, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(.dark)
        .onChange(of: store.storeGameOperation(for: game)) { previous, current in
            if hasStartedInstallation, previous != nil, current == nil { dismiss() }
        }
    }

    private func infoBadge(_ title: String, symbol: String?) -> some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func optionRow<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout)
                .frame(width: 135, alignment: .leading)
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            content()
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    @ViewBuilder private func progressContent(_ operation: StoreGameOperationState) -> some View {
        if let progress = operation.progress {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Installing \(game.name)…")
                            .font(.title3.bold())
                        Text(progress.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let fraction = progress.clampedFraction {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.title2.bold().monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                if let fraction = progress.clampedFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(BorealDownloadProgressStyle())
                } else {
                    ProgressView().progressViewStyle(.linear).tint(.blue)
                }
                HStack {
                    Text(progress.phase.detail)
                    Spacer()
                    Text(progressSummary(progress))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                progressSteps(progress)

                HStack {
                    if let rawDetail = progress.rawDetail {
                        DisclosureGroup("Show details", isExpanded: $showsProgressDetails) {
                            Text(rawDetail)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.top, 8)
                        }
                    }
                    Spacer()
                    if operation.isCancellable {
                        Button("Pause Installation") { store.cancelStoreGameOperation(game) }
                    } else if operation.isResumable {
                        Button("Resume") { store.resumeStoreGameOperation(game) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)

                Label("You can close Boreal. The installation will continue in the background.", systemImage: "lightbulb.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.orange.opacity(0.25)) }
            }
        } else if case .awaitingProvider(let message) = operation {
            statusContent(title: "Continue in \(game.provider.rawValue)", message: message, symbol: game.provider.symbol)
        } else if case .failed(let message) = operation {
            statusContent(title: "Installation failed", message: message, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func progressSteps(_ progress: StoreGameOperationProgress) -> some View {
        let phases: [StoreGameOperationPhase] = [.preparing, .downloading, .installing, .verifying]
        let currentIndex = phases.firstIndex(of: progress.phase) ?? 0
        return VStack(spacing: 0) {
            ForEach(Array(phases.enumerated()), id: \.element) { index, phase in
                HStack(spacing: 11) {
                    Image(systemName: index < currentIndex ? "checkmark.circle.fill" : (index == currentIndex ? "circle.dotted.circle.fill" : "circle.fill"))
                        .foregroundStyle(index < currentIndex ? Color.green : (index == currentIndex ? Color.blue : Color.secondary.opacity(0.35)))
                    Text(phaseStepTitle(phase))
                        .foregroundStyle(index <= currentIndex ? .primary : .secondary)
                    Spacer()
                }
                .padding(.vertical, 9)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10)) }
    }

    private func statusContent(title: String, message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func phaseStepTitle(_ phase: StoreGameOperationPhase) -> String {
        switch phase {
        case .preparing: "Prepare environment"
        case .downloading: "Download game files (\(game.provider.rawValue))"
        case .installing: "Install game files"
        case .verifying: "Finalize installation"
        }
    }

    private func progressSummary(_ progress: StoreGameOperationProgress) -> String {
        var values: [String] = []
        if let transferred = progress.transferred, let total = progress.total {
            values.append("\(transferred) / \(total)")
        } else if let total = progress.total {
            values.append(total)
        }
        if let rate = progress.transferRate { values.append(rate) }
        if let remaining = progress.estimatedTimeRemaining { values.append("~ \(remaining) left") }
        return values.joined(separator: "  •  ")
    }

    private func beginInstallation() {
        hasStartedInstallation = true
        completion(game.provider == .steam ? nil : destination)
    }

    private func chooseExistingInstallation() {
        let panel = NSOpenPanel()
        panel.title = "Locate \(game.name)"
        panel.message = existingInstallationExplanation
        panel.prompt = "Add to Boreal"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types = [UTType(filenameExtension: "exe") ?? .data]
        if installationPlatform == .nativeMacOS { types.append(.applicationBundle) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.registerExistingGame(game, at: url)
        dismiss()
    }

    private var gameSummary: String { game.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var installationPlatform: StoreGameInstallationPlatform {
        store.preferredStoreInstallationPlatform(for: game)
    }
    private var platformName: String { installationPlatform == .nativeMacOS ? "macOS" : "Windows" }
    private var targetEnvironmentName: String {
        if installationPlatform == .nativeMacOS { return "Native macOS application" }
        if game.provider == .steam { return "Boreal · Steam for Windows" }
        return "Boreal · automatic Wine/GPTK environment"
    }
    private var primaryActionTitle: String {
        installationPlatform == .nativeMacOS ? "Install Native Version" : (game.provider == .steam ? "Open Steam Installer" : "Install")
    }
    private var installationExplanation: String {
        if installationPlatform == .nativeMacOS {
            return "Boreal will download the native Mac release and add it to your Library."
        }
        if game.provider == .steam {
            return
                "Boreal will prepare Steam for Windows. Sign in and choose the game library in Steam; Boreal will use that client for installation and launch."
        }
        return
            "Game files will be downloaded from \(game.provider.rawValue). Boreal will inspect the executable, prepare a compatible isolated Windows environment, and add the game to your Library."
    }
    private var existingInstallationExplanation: String {
        installationPlatform == .nativeMacOS
            ? "Choose the installed macOS .app or the main Windows .exe file."
            : "Choose the installed game’s main Windows .exe file."
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            GameArtworkView(game: game, width: 130, height: 195)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 12) {
                Text(game.name)
                    .font(.system(size: 27, weight: .bold))
                    .lineLimit(2)
                HStack(spacing: 9) {
                    infoBadge(game.provider.rawValue, symbol: game.provider.symbol)
                    infoBadge(platformName, symbol: nil)
                    infoBadge(formattedRequiredSize, symbol: nil)
                }
                if !gameSummary.isEmpty {
                    Text(gameSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close")
        }
        .padding(.bottom, 28)
    }

    private var configurationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Installation method", selection: $choice) {
                Label("Install and add to Library", systemImage: "arrow.down.to.line").tag(InstallationChoice.install)
                Label("Use existing installation", systemImage: "folder").tag(InstallationChoice.existing)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            if choice == .install {
                installationOptions
                architectureCard
            } else {
                existingInstallationCard
            }

            actionBar
        }
    }

    private var installationOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installation options", systemImage: "gearshape")
                .font(.headline)
            VStack(spacing: 0) {
                optionRow(title: "Target environment", symbol: installationPlatform == .nativeMacOS ? "apple.logo" : "wineglass") {
                    Text(targetEnvironmentName).lineLimit(1)
                }
                Divider().opacity(0.45)
                optionRow(title: "Installation path", symbol: "folder") {
                    if game.provider == .steam {
                        Text("Selected in Steam").foregroundStyle(.secondary)
                    } else {
                        Text(destination.path).lineLimit(1).truncationMode(.middle)
                        Button("Change…") { chooseDestination() }
                    }
                }
                Divider().opacity(0.45)
                HStack(spacing: 10) {
                    storageSummary(title: "Download", value: formattedDownloadSize, symbol: "arrow.down.circle")
                    storageSummary(title: "Required", value: formattedRequiredSize, symbol: "internaldrive")
                    storageSummary(title: "Available", value: formattedCapacity, symbol: "externaldrive")
                }
                .padding(12)
            }
            .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10)) }
        }
    }

    private var existingInstallationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Use an existing installation", systemImage: "folder.badge.plus")
                .font(.headline)
            Text(existingInstallationExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.blue.opacity(0.35)) }
    }

    private var architectureCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("What will happen?", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            Text(installationExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            architectureSummary
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.blue.opacity(0.35)) }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .controlSize(.large)
            Button(choice == .install ? primaryActionTitle : "Choose Installed Game…", systemImage: choice == .install ? "arrow.down.to.line" : "folder") {
                if choice == .install { beginInstallation() } else { chooseExistingInstallation() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(choice == .install && game.provider != .steam && !destinationIsUsable)
        }
        .padding(.top, 4)
    }

    private var destinationIsUsable: Bool {
        BorealStore.gameInstallationDestinationIsAvailable(destination)
    }

    private var formattedDownloadSize: String {
        guard let bytes = game.sizeEstimate?.downloadBytes, bytes > 0 else { return String(localized: .Library.notProvided) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var formattedRequiredSize: String {
        if let bytes = game.storageBytes, bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        guard let estimate = game.sizeEstimate,
            let bytes = estimate.installedBytes, bytes > 0
        else { return "Unavailable" }
        let value = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return estimate.source.isExactManifest ? value : "≈ \(value)"
    }

    private var formattedCapacity: String {
        guard game.provider != .steam else { return "Shown by Steam" }
        guard let bytes = GameStorage.availableCapacity(at: capacityProbeURL) else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @ViewBuilder private var architectureSummary: some View {
        if installationPlatform != .nativeMacOS {
            if let architecture = game.sizeEstimate?.executableArchitecture {
                let requiresWine = architecture == .x86
                Label(
                    requiresWine
                        ? "32-bit Windows game · Wine with WoW64 required"
                        : "64-bit Windows game · Wine or GPTK can be prepared",
                    systemImage: requiresWine ? "exclamationmark.shield.fill" : "checkmark.shield.fill"
                )
                .foregroundStyle(requiresWine ? .orange : .green)
                Text("Detected from store metadata before download. Boreal will verify the installed executable again before creating its runtime environment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Windows architecture unknown", systemImage: "questionmark.diamond")
                    .foregroundStyle(.secondary)
                Text(
                    "The store did not publish enough information to distinguish a 32-bit game from a 64-bit game. Boreal will inspect the executable after installation."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var capacityProbeURL: URL {
        var candidate = destination
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    private func storageSummary(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.medium)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Game Installation Location"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        if panel.runModal() == .OK, let selected = panel.url {
            destination = selected.standardizedFileURL
        }
    }
}
