import SwiftUI

struct DownloadsView: View {
    @Environment(BorealStore.self) private var store
    @AppStorage("developerMode") private var developerMode = false
    @State private var showsRuntimeDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Components").font(.title2).fontWeight(.semibold)
                    Text("Boreal installs shared Windows components only when an app needs them.").foregroundStyle(.secondary)
                }
                if let operation = store.runtimeOperationDetail {
                    VStack(spacing: 13) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        Text("Setting up Boreal").font(.headline)
                        Text(operation).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        ProgressView()
                            .controlSize(.large)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
                    .padding(.top, 42)
                } else if store.runtimeStatuses.contains(where: isInstalledRuntime) {
                    runtimeList
                } else if let runtime = store.runtimeStatuses.first(where: { $0.state == .available }) {
                    prerequisiteView(for: runtime)
                } else {
                    unavailableView
                }
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .task { await store.refreshRuntimeStatuses() }
    }

    private func isInstalledRuntime(_ runtime: RuntimeStatus) -> Bool {
        runtime.source == .installed
    }

    private var runtimeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.runtimeStatuses.enumerated()), id: \.element.id) { index, runtime in
                HStack(spacing: 14) {
                    Image(systemName: runtime.isVerified ? "checkmark.seal.fill" : "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(runtime.isVerified ? Color.green : Color.accentColor)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(runtime.name).font(.headline)
                        Text(runtimeDetail(runtime)).font(.callout).foregroundStyle(.secondary)
                        if developerMode {
                            Text("Wine \(runtime.wineVersion) · \(runtime.architecture.rawValue)")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    runtimeAction(runtime)
                }.padding(16)
                if index < store.runtimeStatuses.count - 1 { Divider().padding(.leading, 66) }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.7), lineWidth: 0.5))
    }

    private func prerequisiteView(for runtime: RuntimeStatus) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "shippingbox")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Boreal Runtime Required").font(.title3).fontWeight(.semibold)
            Text("Components depend on the Boreal Runtime.\nInstall it to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Install Runtime") { store.prepareRuntime(id: runtime.id) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            Button("Check Again") { Task { await store.refreshRuntimeStatuses() } }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
        .padding(.top, 42)
    }

    @ViewBuilder private var unavailableView: some View {
        if let candidate = store.localRuntimeCandidates.first {
            localRuntimeView(candidate)
        } else {
            switch store.runtimeDiscoveryState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Checking for Boreal Runtime…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
        case .loaded, .failed:
            VStack(spacing: 13) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text("Runtime Unavailable").font(.title3).fontWeight(.semibold)
                Text("Boreal couldn't find a compatible runtime.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Check Again", systemImage: "arrow.clockwise") { Task { await store.refreshRuntimeStatuses() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                Button(showsRuntimeDetails ? "Hide Details" : "Show Details") {
                    withAnimation { showsRuntimeDetails.toggle() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                if showsRuntimeDetails {
                    Text(runtimeDetails)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
            .padding(.top, 42)
            }
        }
    }

    private func localRuntimeView(_ candidate: LocalRuntimeCandidate) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Use Installed Wine").font(.title3).fontWeight(.semibold)
            Text("Boreal found \(candidate.displayName) \(candidate.wineVersion). It can copy and validate this installation as an isolated, read-only runtime snapshot.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 540)
            Button("Import \(candidate.displayName)", systemImage: "square.and.arrow.down") {
                store.importLocalRuntime(id: candidate.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
            Text("The original app stays unchanged. Boreal validates the copy and runs a Wine prefix smoke test before making it available.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
        .padding(.top, 42)
    }

    private var runtimeDetails: String {
        if case .failed(let details) = store.runtimeDiscoveryState { return details }
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif
        return "Runtime catalog\nNo compatible runtime returned.\n\nArchitecture: \(architecture)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nChannel: stable"
    }

    private func runtimeDetail(_ runtime: RuntimeStatus) -> String {
        if let detail = runtime.detail { return detail }
        switch runtime.state {
        case .installed:
            if runtime.origin == .localImport { return runtime.isVerified ? "Installed · Validated local snapshot" : "Installed local snapshot" }
            return runtime.isVerified ? "Installed · Verified catalog runtime" : "Installed"
        case .available:
            if let size = runtime.compressedSize, size > 0 { return "Windows compatibility runtime · \(store.formattedBytes(size))" }
            return "Windows compatibility runtime"
        case .preparing: return "Downloading and verifying…"
        case .needsAttention: return "Needs Attention"
        case .loading: return "Checking…"
        }
    }

    @ViewBuilder private func runtimeAction(_ runtime: RuntimeStatus) -> some View {
        switch runtime.state {
        case .installed:
            Label(runtime.origin == .localImport ? "Validated" : "Verified", systemImage: "checkmark").foregroundStyle(.secondary)
        case .available:
            Button("Download") { store.prepareRuntime(id: runtime.id) }.buttonStyle(.bordered)
        case .preparing, .loading:
            ProgressView().controlSize(.small)
        case .needsAttention:
            Label("Needs Attention", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
