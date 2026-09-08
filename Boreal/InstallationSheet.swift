import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InstallationSheet: View {
    private enum InstallerSheetAction: String, CaseIterable, Hashable {
        case install
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
        }
    }

    @ViewBuilder private var content: some View {
        switch store.installation.state {
        case .idle:
                Picker("Action", selection: $selectedAction) {
                    Text("Install and add to Library").tag(InstallerSheetAction.install)
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
                }
                DisclosureGroup("Installation Details", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(candidate.fileType) setup file", systemImage: "doc")
                        if selectedAction == .runOnly {
                            Label("Runs with \(selectedRuntimeEngine.displayName)", systemImage: "cpu")
                            Label("No game detection or native installation", systemImage: "checkmark.shield")
                        } else {
                            Label("Configuration selected automatically", systemImage: "cpu")
                        }
                        Label("Isolated Windows environment", systemImage: "externaldrive")
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
                selectedAction == .runOnly ? "Installer launched" : "First launch verified",
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
                selectedAction == .runOnly ? "Installer launch cancelled" : "Incomplete environment removed",
                systemImage: "checkmark.circle.fill"
            )
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder private var installationSteps: some View {
        let stages = selectedAction == .runOnly
            ? [InstallationStage.preparingRuntime, .creatingEnvironment, .startingInstaller]
            : InstallationStage.allCases
        VStack(alignment: .leading, spacing: 9) {
            ForEach(stages, id: \.self) { stage in
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

    @ViewBuilder private var actions: some View {
        switch store.installation.state {
        case .idle:
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Use Existing Game…", systemImage: "folder.badge.plus") {
                    chooseExistingGame()
                }
                Button(selectedAction == .runOnly ? "Run Installer" : "Install", systemImage: selectedAction == .runOnly ? "play.fill" : "arrow.down.circle.fill") { beginAction() }
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
                Button(selectedAction == .runOnly ? "View in Library" : "Open", systemImage: selectedAction == .runOnly ? "shippingbox.fill" : "play.fill") { completion(id); dismiss() }
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
        store.addExistingWindowsApp(at: url)
        dismiss()
    }

    private var installationFraction: Double {
        let stages = selectedAction == .runOnly
            ? [InstallationStage.preparingRuntime, .creatingEnvironment, .startingInstaller]
            : InstallationStage.allCases
        guard let stage = store.installation.stage,
              let index = stages.firstIndex(of: stage) else { return 0 }
        return Double(index) / Double(max(stages.count - 1, 1))
    }

    private var installationPercentage: Int {
        Int((installationFraction * 100).rounded())
    }

    private var title: String {
        switch store.installation.state {
        case .idle: selectedAction == .runOnly ? "Run \(candidate.name)" : "Install \(candidate.name)"
        case .installing: selectedAction == .runOnly ? "Starting \(candidate.name)" : "Installing \(candidate.name)"
        case .succeeded: selectedAction == .runOnly ? "Installer is running" : "\(candidate.name) is ready"
        case .failed: selectedAction == .runOnly ? "Installer Couldn’t Start" : "Installation Failed"
        case .cancelled: selectedAction == .runOnly ? "Installer Launch Cancelled" : "Installation Cancelled"
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
                : "Boreal checked that the application opens correctly."
        case .failed: selectedAction == .runOnly
                ? "\(candidate.name) could not be launched."
                : "\(candidate.name) wasn’t added to your Library."
        case .cancelled: selectedAction == .runOnly
                ? "The installer launch was stopped and the incomplete environment was removed."
                : "The installer was stopped and the incomplete environment was removed."
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
        if selectedAction == .runOnly {
            store.beginInstallerLaunch(candidate, runtimeEngine: selectedRuntimeEngine)
        } else {
            beginInstallation()
        }
    }
}
