import SwiftUI

struct InstallationSheet: View {
    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let candidate: InstallCandidate
    let completion: (UUID) -> Void
    @State private var showsDetails = false

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
        .onAppear { store.resetInstallation() }
    }

    @ViewBuilder private var content: some View {
        switch store.installation.state {
        case .idle:
                DisclosureGroup("Installation Details", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(candidate.fileType) setup file", systemImage: "doc")
                        Label("Configuration selected automatically", systemImage: "cpu")
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
            Label("First launch verified", systemImage: "checkmark.seal.fill")
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
            Label("Incomplete environment removed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var installationSteps: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(InstallationStage.allCases, id: \.self) { stage in
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
                Button("Install") { beginInstallation() }
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
                Button("Open", systemImage: "play.fill") { completion(id); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .failed, .cancelled:
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                Button("Try Again", systemImage: "arrow.clockwise") { beginInstallation() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isInstalling: Bool {
        if case .installing = store.installation.state { true } else { false }
    }

    private var installationFraction: Double {
        let stages = InstallationStage.allCases
        guard let stage = store.installation.stage,
              let index = stages.firstIndex(of: stage) else { return 0 }
        return Double(index) / Double(max(stages.count - 1, 1))
    }

    private var installationPercentage: Int {
        Int((installationFraction * 100).rounded())
    }

    private var title: String {
        switch store.installation.state {
        case .idle: "Install \(candidate.name)"
        case .installing: "Installing \(candidate.name)"
        case .succeeded: "\(candidate.name) is ready"
        case .failed: "Installation Failed"
        case .cancelled: "Installation Cancelled"
        }
    }

    private var message: String {
        switch store.installation.state {
        case .idle: "Boreal will prepare the best environment for this application."
        case .installing: store.installation.stage?.userMessage ?? "Preparing installation…"
        case .succeeded: "Boreal checked that the application opens correctly."
        case .failed: "\(candidate.name) wasn’t added to your Library."
        case .cancelled: "The installer was stopped and the incomplete environment was removed."
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
}
