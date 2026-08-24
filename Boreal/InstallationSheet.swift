import SwiftUI

struct InstallationSheet: View {
    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let candidate: InstallCandidate
    let completion: (UUID) -> Void
    @State private var isInstalling = false
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 24) {
            AppIconView(symbol: "shippingbox.fill", size: 88)
            VStack(spacing: 7) {
                Text(isInstalling ? "Installing \(candidate.name)" : "Install \(candidate.name)").font(.title2).fontWeight(.semibold)
                Text(isInstalling ? store.installStage : "Boreal will prepare the best environment for this application.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }

            if isInstalling {
                ProgressView(value: store.installProgress ?? 0).frame(width: 320)
            } else {
                DisclosureGroup("Installation Details", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(candidate.fileType) setup file", systemImage: "doc")
                        Label("64-bit configuration will be selected automatically", systemImage: "cpu")
                        Label("Isolated Windows environment", systemImage: "externaldrive")
                    }
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(width: 360)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.disabled(isInstalling)
                Spacer()
                Button("Install") {
                    isInstalling = true
                    Task {
                        if let id = await store.install(candidate) { completion(id); dismiss() }
                        else { isInstalling = false }
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(isInstalling)
            }.frame(width: 360)
        }
        .padding(34)
        .frame(minWidth: 470, minHeight: 390)
        .interactiveDismissDisabled(isInstalling)
    }
}
