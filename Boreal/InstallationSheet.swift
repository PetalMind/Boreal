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
        VStack(alignment: .leading, spacing: 0) {
            header
            content
            actions
        }
        .padding(28)
        .frame(width: 650)
        .frame(minHeight: 520)
        .background(
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.13), Color(red: 0.055, green: 0.06, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isInstalling)
        .onAppear {
            store.resetInstallation()
            selectedRuntimeEngine = candidate.recommendedRuntimeEngine
            selectedAction = candidate.canBeRegisteredAsExistingGame ? .existing : .install
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            AppIconView(symbol: iconSymbol, size: 96)
                .frame(width: 112, height: 112)
                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 9) {
                Text(candidate.name)
                    .font(.system(size: 27, weight: .bold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    metadataBadge(candidate.fileType, symbol: "doc.fill")
                    metadataBadge("Windows", symbol: "desktopcomputer")
                    metadataBadge(selectedRuntimeLabel, symbol: "wineglass")
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(message)
            }
            .padding(.top, 5)
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isInstalling)
            .accessibilityLabel("Close")
        }
        .padding(.bottom, 28)
    }

    private func metadataBadge(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func optionRow<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout)
                .frame(width: 110, alignment: .leading)
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            content().font(.callout)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What will happen?", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            Text(actionExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Technical details", isExpanded: $showsDetails) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("\(candidate.fileType) \(selectedAction == .existing ? "game file" : "setup file")", systemImage: "doc")
                    if selectedAction == .runOnly {
                        Label("Runs with \(selectedRuntimeEngine.displayName) · \(selectedRuntimeEngine.graphicsName)", systemImage: "cpu")
                    } else if selectedAction == .existing {
                        Label("The selected executable remains in its current location", systemImage: "folder")
                    } else {
                        Label("Uses \(selectedRuntimeEngine.displayName) · \(selectedRuntimeEngine.graphicsName)", systemImage: "cpu")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.blue.opacity(0.35)) }
    }

    private var selectedRuntimeLabel: String {
        selectedRuntimeEngine.displayName
    }

    private var actionSymbol: String {
        switch selectedAction {
        case .install: "arrow.down.to.line"
        case .existing: "folder.badge.plus"
        case .runOnly: "play.fill"
        }
    }

    private var actionDescription: String {
        switch selectedAction {
        case .install: "Install and add to Library"
        case .existing: "Register existing game"
        case .runOnly: "Run installer once"
        }
    }

    private var actionExplanation: String {
        switch selectedAction {
        case .install:
            "Boreal will inspect the installer, prepare a compatible isolated Windows environment, run setup, detect the installed game, and add it to your Library."
        case .existing:
            "Boreal will prepare an isolated environment and register this executable without launching it or moving the existing game files."
        case .runOnly:
            "Boreal will prepare an isolated environment and launch this file with the selected runtime. It will not detect or add a game to your Library."
        }
    }

    private var installationLocation: String {
        if selectedAction == .existing {
            return candidate.url.deletingLastPathComponent().path
        }
        return "Managed Boreal environment · final folder selected in the installer"
    }

    private func revealSelectedFile() {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
    }

    private func revealSelectedGameLocation() {
        NSWorkspace.shared.open(candidate.url.deletingLastPathComponent())
    }

    @ViewBuilder private var content: some View {
        switch store.installation.state {
        case .idle:
            VStack(alignment: .leading, spacing: 14) {
                Picker("Action", selection: $selectedAction) {
                    Text("Install and add to Library").tag(InstallerSheetAction.install)
                    if candidate.canBeRegisteredAsExistingGame {
                        Text("Add existing game").tag(InstallerSheetAction.existing)
                    }
                    Text("Run installer only").tag(InstallerSheetAction.runOnly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Setup options", systemImage: "gearshape")
                        .font(.headline)
                    VStack(spacing: 0) {
                        optionRow(title: "Selected file", symbol: "doc") {
                            Text(candidate.url.path).lineLimit(1).truncationMode(.middle)
                            Button("Show") { revealSelectedFile() }
                        }
                        Divider().opacity(0.45)
                        optionRow(title: selectedAction == .existing ? "Game location" : "Install location", symbol: "folder") {
                            Text(installationLocation)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if selectedAction == .existing {
                                Button("Show") { revealSelectedGameLocation() }
                            }
                        }
                        Divider().opacity(0.45)
                        optionRow(title: "Action", symbol: actionSymbol) {
                            Text(actionDescription)
                        }
                        Divider().opacity(0.45)
                        optionRow(title: "Environment", symbol: "wineglass") {
                            Picker("Run with", selection: $selectedRuntimeEngine) {
                                ForEach(RuntimeEngine.allCases, id: \.self) { engine in
                                    Text(engine.displayName + " · " + engine.graphicsName).tag(engine)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10)) }
                }

                informationCard
            }
        case .installing:
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title3.bold())
                        Text(store.installation.stage?.userMessage ?? "Preparing installation…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(installationPercentage)%")
                        .font(.title2.bold().monospacedDigit())
                        .contentTransition(.numericText())
                }
                ProgressView(value: installationFraction)
                    .progressViewStyle(BorealDownloadProgressStyle())
                installationSteps
                    .padding(16)
                    .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.10)) }
                Label("You may keep using Boreal while this operation finishes.", systemImage: "info.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.blue)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        case .succeeded:
            Label(
                selectedAction == .runOnly ? "Installer launched" : (selectedAction == .existing ? "Game added" : "Compatibility prepared"),
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
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .controlSize(.large)
                Button(primaryActionTitle, systemImage: primaryActionSymbol) { beginAction() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 18)
        case .installing:
            HStack {
                Spacer()
                Button("Cancel Installation", role: .cancel) { store.cancelInstallation() }
                    .controlSize(.large)
            }
            .padding(.top, 18)
        case .succeeded(let id):
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                Button(successActionTitle, systemImage: successActionSymbol) { completion(id); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 18)
        case .failed, .cancelled:
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                Button("Try Again", systemImage: "arrow.clockwise") { beginAction() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 18)
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
            store.addExistingWindowsApp(at: url, runtimeEngine: selectedRuntimeEngine)
            return
        }
        selectedAction = .existing
        store.addExistingWindowsApp(at: url, runtimeEngine: selectedRuntimeEngine)
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
        store.beginInstallation(candidate, runtimeEngine: selectedRuntimeEngine)
    }

    private func beginAction() {
        switch selectedAction {
        case .runOnly:
            store.beginInstallerLaunch(candidate, runtimeEngine: selectedRuntimeEngine)
        case .existing:
            store.addExistingWindowsApp(at: candidate.url, runtimeEngine: selectedRuntimeEngine)
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
