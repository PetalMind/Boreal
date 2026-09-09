import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InstallationSheet: View {
    private enum InstallerSheetAction: String, CaseIterable, Hashable {
        case install
        case existing
        case runOnly
    }

    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let candidate: InstallCandidate
    let completion: (UUID) -> Void
    @State private var showsDetails = false
    @State private var selectedAction: InstallerSheetAction = .install
    @State private var selectedRuntimeEngine: RuntimeEngine = .wine

    var body: some View {
        VStack(spacing: 24) {
            AppIconView(symbol: iconSymbol, size: 88)
            VStack(spacing: 7) {
                Text(title).font(.title2).fontWeight(.semibold)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .accessibilityLabel(message)
            }

            content
            actions.frame(width: 390)   
        }
        .padding(34)
        .frame(minWidth: 500, minHeight: 420)
        .interactiveDismissDisabled(isInstalling)
        .onAppear {
            store.resetInstallation()
            selectedRuntimeEngine = candidate.recommendedRuntimeEngine
            selectedAction = candidate.canBeRegisteredAsExistingGame ? .existing : .install
        }
    }

    @ViewBuilder private var content: some View {
        switch store.installation.state {
        case .idle:
                Picker("Action", selection: $selectedAction) {
                    Text("Install and add to Library").tag(InstallerSheetAction.install)
                    if candidate.canBeRegisteredAsExistingGame {
                        Text("Add existing game").tag(InstallerSheetAction.existing)
                    }
                    Text("Run installer only").tag(InstallerSheetAction.runOnly)
                }
                .pickerStyle(.segmented)
                .frame(width: 390)

                if selectedAction == .runOnly {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Run with", selection: $selectedRuntimeEngine) {
                            ForEach(RuntimeEngine.allCases, id: \.self) { engine in
                                Label(engine.displayName + " (" + engine.graphicsName + ")", systemImage: engine == .gamePortingToolkit ? "cpu" : "shippingbox")
                                    .tag(engine)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("Boreal will launch this file directly. It will not detect a game, start a first launch, or install a native macOS version.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 390, alignment: .leading)
                } else if selectedAction == .existing {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("The selected game will be added without launching it.", systemImage: "checkmark.shield.fill")
                        Text("Boreal will prepare an isolated environment and register this executable. It will not perform a first launch or run the game during setup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 390, alignment: .leading)
                }
                DisclosureGroup("Installation Details", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(candidate.fileType) \(selectedAction == .existing ? "game file" : "setup file")", systemImage: "doc")
                        if selectedAction == .runOnly {
                            Label("Runs with \(selectedRuntimeEngine.displayName)", systemImage: "cpu")
                            Label("No game detection or native installation", systemImage: "checkmark.shield")
                        } else if selectedAction == .existing {
                            Label("Adds the selected game without launching it", systemImage: "checkmark.shield")
                            Label("Existing Windows environment", systemImage: "externaldrive")
                        } else {
                            Label("Configuration selected automatically", systemImage: "cpu")
                        }
                        if selectedAction != .existing {
                            Label("Isolated Windows environment", systemImage: "externaldrive")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 390)
        case .installing:
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.installation.stage?.title ?? "Preparing")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(installationPercentage)%")
                        .font(.title3.bold().monospacedDigit())
                        .contentTransition(.numericText())
                }
                ProgressView(value: installationFraction)
                    .progressViewStyle(BorealDownloadProgressStyle())
                    .frame(width: 340)
                DisclosureGroup("Show Details", isExpanded: $showsDetails) {
                    installationSteps.padding(.top, 8)
                }
            }
            .frame(width: 390)
        case .succeeded:
            Label(
                selectedAction == .runOnly ? "Installer launched" : (selectedAction == .existing ? "Game added" : "First launch verified"),
                systemImage: selectedAction == .runOnly ? "shippingbox.fill" : "checkmark.seal.fill"
            )
                .foregroundStyle(.green)
        case .failed:
            VStack(alignment: .leading, spacing: 12) {
                if store.installation.rollbackCompleted {
                    Label("Incomplete environment removed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No partial installation was left behind.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup("Show Details", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let stage = store.installation.stage { Text("Stage: \(stage.title)") }
                        Text(store.installation.failureMessage ?? "Unknown installation error")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.top, 8)
                }
            }
            .frame(width: 390, alignment: .leading)
        case .cancelled:
            Label(
                selectedAction == .runOnly ? "Installer launch cancelled" : (selectedAction == .existing ? "Game addition cancelled" : "Incomplete environment removed"),
                systemImage: "checkmark.circle.fill"
            )
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder private var installationSteps: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(installationStages, id: \.self) { stage in
                HStack(spacing: 9) {
                    if store.installation.completedStages.contains(stage) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if store.installation.stage == stage {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "circle").foregroundStyle(.tertiary)
                    }
                    Text(stage.title)
                        .foregroundStyle(store.installation.stage == stage ? .primary : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var installationStages: [InstallationStage] {
        switch selectedAction {
        case .runOnly:
            return [.preparingRuntime, .creatingEnvironment, .startingInstaller]
        case .existing:
            return [.preparingRuntime, .creatingEnvironment, .committing]
        case .install:
            return InstallationStage.allCases
        }
    }

    @ViewBuilder private var actions: some View {
        switch store.installation.state {
        case .idle:
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Use Existing Game…", systemImage: "folder.badge.plus") {
                    chooseExistingGame()
                }
                Button(primaryActionTitle, systemImage: primaryActionSymbol) { beginAction() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .installing:
            HStack {
                Button("Cancel Installation", role: .cancel) { store.cancelInstallation() }
                Spacer()
            }
        case .succeeded(let id):
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                Button(successActionTitle, systemImage: successActionSymbol) { completion(id); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .failed, .cancelled:
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                Button("Try Again", systemImage: "arrow.clockwise") { beginAction() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isInstalling: Bool {
        if case .installing = store.installation.state { true } else { false }
    }

    private func chooseExistingGame() {
        let panel = NSOpenPanel()
        panel.title = "Choose Existing Windows Game"
        panel.message = "Choose the main .exe file of an already installed Windows game."
        panel.prompt = "Use Game"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.caseInsensitiveCompare("exe") == .orderedSame,
              FileManager.default.fileExists(atPath: url.path),
              ExecutableDiscovery.isEligibleExecutablePath(url.lastPathComponent) else {
            store.addExistingWindowsApp(at: url)
            return
        }
        selectedAction = .existing
        store.addExistingWindowsApp(at: url)
    }

    private var installationFraction: Double {
        guard let stage = store.installation.stage,
              let index = installationStages.firstIndex(of: stage) else { return 0 }
        return Double(index) / Double(max(installationStages.count - 1, 1))
    }

    private var installationPercentage: Int {
        Int((installationFraction * 100).rounded())
    }

    private var title: String {
        switch store.installation.state {
        case .idle: selectedAction == .runOnly ? "Run \(candidate.name)" : (selectedAction == .existing ? "Add \(candidate.name)" : "Install \(candidate.name)")
        case .installing: selectedAction == .runOnly ? "Starting \(candidate.name)" : (selectedAction == .existing ? "Adding \(candidate.name)" : "Installing \(candidate.name)")
        case .succeeded: selectedAction == .runOnly ? "Installer is running" : "\(candidate.name) is ready"
        case .failed: selectedAction == .runOnly ? "Installer Couldn’t Start" : "Installation Failed"
        case .cancelled: selectedAction == .runOnly ? "Installer Launch Cancelled" : (selectedAction == .existing ? "Game Addition Cancelled" : "Installation Cancelled")
        }
    }

    private var message: String {
        switch store.installation.state {
        case .idle: selectedAction == .runOnly
                ? "Choose a compatibility runtime and launch the installer directly."
                : "Boreal will prepare the best environment for this application."
        case .installing: store.installation.stage?.userMessage ?? "Preparing installation…"
        case .succeeded: selectedAction == .runOnly
                ? "The installer was launched directly. Boreal did not install or detect the game for you."
                : (selectedAction == .existing
                    ? "The game was added without being launched."
                    : "Boreal checked that the application opens correctly.")
        case .failed: selectedAction == .runOnly
                ? "\(candidate.name) could not be launched."
                : "\(candidate.name) wasn’t added to your Library."
        case .cancelled: selectedAction == .runOnly
                ? "The installer launch was stopped and the incomplete environment was removed."
                : (selectedAction == .existing
                    ? "The game addition was stopped and the incomplete environment was removed."
                    : "The installer was stopped and the incomplete environment was removed.")
        }
    }

    private var iconSymbol: String {
        switch store.installation.state {
        case .succeeded: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        default: "shippingbox.fill"
        }
    }

    private func beginInstallation() {
        store.beginInstallation(candidate)
    }

    private func beginAction() {
        switch selectedAction {
        case .runOnly:
            store.beginInstallerLaunch(candidate, runtimeEngine: selectedRuntimeEngine)
        case .existing:
            store.addExistingWindowsApp(at: candidate.url)
        case .install:
            beginInstallation()
        }
    }

    private var primaryActionTitle: String {
        switch selectedAction {
        case .runOnly: "Run Installer"
        case .existing: "Add Game"
        case .install: "Install"
        }
    }

    private var primaryActionSymbol: String {
        switch selectedAction {
        case .runOnly: "play.fill"
        case .existing: "folder.badge.plus"
        case .install: "arrow.down.circle.fill"
        }
    }

    private var successActionTitle: String {
        selectedAction == .install ? "Open" : "View in Library"
    }

    private var successActionSymbol: String {
        selectedAction == .install ? "play.fill" : "folder"
    }
}
