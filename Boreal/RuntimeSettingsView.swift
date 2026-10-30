import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RuntimeSettingsView: View {
    @Environment(BorealStore.self) private var store
    @AppStorage("automaticRuntimeUpdates") private var automaticRuntimeUpdates = true
    @AppStorage("automaticDXVKUpdates") private var automaticDXVKUpdates = true
    @AppStorage("automaticVKD3DUpdates") private var automaticVKD3DUpdates = true
    @State private var runtimeToEdit: RuntimeStatus?
    @State private var runtimeToRemove: RuntimeStatus?
    @State private var showsMSyncBuilder = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(.Settings.borealRuntimeTitle, subtitle: .Settings.borealRuntimeSubtitle, symbol: "gearshape.2.fill") {
                    SettingsRow(.Settings.automaticRuntimeUpdatesLabel) { Toggle("", isOn: $automaticRuntimeUpdates).labelsHidden() }
                }
                SettingsCard(.Settings.graphicsComponentsTitle, subtitle: .Settings.graphicsComponentsSubtitle, symbol: "display") {
                    SettingsRow(.Settings.automaticDXVKUpdatesLabel) { Toggle("", isOn: $automaticDXVKUpdates).labelsHidden() }
                    Divider()
                    SettingsRow(.Settings.automaticVKD3DupdatesLabel) { Toggle("", isOn: $automaticVKD3DUpdates).labelsHidden() }
                }
                runtimeImportCard
                SettingsCard(
                    "Wine with MSync", subtitle: "Build an additional Wine 9.15 runtime from source with the official MSync patch.", symbol: "hammer.fill"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "Requires Xcode tools, Bison, Flex and MinGW. Intel libraries are prepared automatically. Apple silicon also requires Rosetta. Compilation can take a long time."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        Button("Prepare Wine with MSync…", systemImage: "hammer") { showsMSyncBuilder = true }
                            .buttonStyle(.bordered)
                            .disabled(store.runtimeOperationDetail != nil)
                    }
                }
                installedRuntimesCard
            }
            .padding(.horizontal, 32).padding(.bottom, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await store.refreshRuntimeStatuses() }
            .sheet(isPresented: $showsMSyncBuilder) {
                WineMSyncBuildSheet { prefix in
                    showsMSyncBuilder = false
                    store.buildMSyncRuntime(dependencyPrefix: prefix)
                }
            }
            .sheet(item: $runtimeToEdit) { runtime in
                RuntimeEditorSheet(runtime: runtime) { name in
                    store.renameRuntime(id: runtime.id, to: name)
                    runtimeToEdit = nil
                }
            }
            .alert(
                "Remove Runtime?",
                isPresented: Binding(
                    get: { runtimeToRemove != nil },
                    set: { if !$0 { runtimeToRemove = nil } }
                )
            ) {
                Button("Remove", role: .destructive) {
                    guard let runtime = runtimeToRemove else { return }
                    runtimeToRemove = nil
                    store.removeRuntime(id: runtime.id)
                }
                Button("Cancel", role: .cancel) { runtimeToRemove = nil }
            } message: {
                Text(
                    runtimeToRemove.map {
                        "This removes the immutable \($0.name) snapshot from Boreal. Environments using it must be removed first."
                    } ?? "")
            }
    }

    private var installedRuntimesCard: some View {
        SettingsCard(
            "Installed runtimes",
            subtitle: "Wine and GPTK hosts with their installed graphics components. Expand variants to manage existing snapshots.",
            symbol: "shippingbox.fill"
        ) {
            let runtimes = store.runtimeStatuses.filter { $0.source == .installed }
            if let operation = store.runtimeOperationDetail {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            if runtimes.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                    Text("No runtime is installed yet. Import or install one from Downloads.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                let families = RuntimeFamily.group(runtimes)
                ForEach(families) { family in
                    VStack(alignment: .leading, spacing: 8) {
                        runtimeRow(family.primary, showsComponents: false)
                        RuntimeGraphicsComponentsView(components: family.graphicsComponents)
                        if family.deployments.count > 1 {
                            DisclosureGroup("Other installed variants") {
                                ForEach(family.deployments.dropFirst()) { runtime in
                                    runtimeRow(runtime)
                                }
                            }
                            .font(.callout)
                        }
                    }
                    if family.id != families.last?.id { Divider() }
                }
            }
        }
    }

    private var runtimeImportCard: some View {
        SettingsCard(
            "Import runtimes",
            subtitle: "Import a Wine or GPTK host, or add Apple's D3DMetal graphics component to a compatible host. Original app bundles are never modified.",
            symbol: "square.and.arrow.down"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "cpu.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Game Porting Toolkit")
                            .font(.headline)
                        Text("Choose a GPTK app or extracted Apple D3DMetal evaluation payload. GPTK 4 is layered only onto a GPTK-capable Wine 11.17+ host.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("Import…", systemImage: "square.and.arrow.down") { selectGPTKRuntime() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.runtimeOperationDetail != nil)
                }

                let candidates = store.localRuntimeCandidates
                if candidates.isEmpty {
                    Text("No local runtime bundle was detected in Applications. You can select one manually above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Divider()
                    Text("Detected local bundles")
                        .font(.subheadline.weight(.semibold))
                    ForEach(candidates) { candidate in
                        HStack(spacing: 10) {
                            Image(systemName: candidate.engine == .gamePortingToolkit ? "cpu" : "shippingbox")
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.displayName)
                                Text("\(candidate.engine.displayName) · \(candidate.wineVersion) · \(candidate.architecture.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Import") { store.importLocalRuntime(id: candidate.id) }
                                .buttonStyle(.bordered)
                                .disabled(store.runtimeOperationDetail != nil)
                        }
                    }
                }
            }
        }
    }

    private func runtimeRow(_ runtime: RuntimeStatus, showsComponents: Bool = true) -> some View {
        let environmentCount = store.environments.filter { $0.runtimeID == runtime.id }.count
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: runtime.isVerified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(runtime.isVerified ? Color.green : Color.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(runtime.name)
                    .font(.headline)
                Text("\(runtime.engine.displayName) · \(runtime.wineVersion) · \(runtime.architecture.rawValue)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if showsComponents, !runtime.componentSummary.isEmpty {
                    Text(runtime.componentSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if environmentCount > 0 {
                    Text("Used by \(environmentCount) \(environmentCount == 1 ? "environment" : "environments")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(runtime.isVerified ? "Verified and available" : "Needs attention")
                        .font(.caption)
                        .foregroundStyle(runtime.isVerified ? Color.secondary : Color.orange)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button("Edit") { runtimeToEdit = runtime }
                    .buttonStyle(.bordered)
                Button("Remove", role: .destructive) { runtimeToRemove = runtime }
                    .buttonStyle(.bordered)
                    .disabled(environmentCount > 0 || store.runtimeOperationDetail != nil)
            }
        }
        .padding(.vertical, 10)
    }

    private func selectGPTKRuntime() {
        let panel = NSOpenPanel()
        panel.title = "Import Game Porting Toolkit"
        panel.message =
            "Choose a GPTK app bundle or an extracted Apple evaluation payload containing D3DMetal. A standalone GPTK 4 payload also requires a GPTK-capable x86_64 Wine 11.17+ host."
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle, .folder]
        guard panel.runModal() == .OK, let source = panel.url else { return }
        store.importGPTKRuntime(from: source)
    }
}

private struct RuntimeEditorSheet: View {
    let runtime: RuntimeStatus
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(runtime: RuntimeStatus, onSave: @escaping (String) -> Void) {
        self.runtime = runtime
        self.onSave = onSave
        _name = State(initialValue: runtime.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Edit runtime")
                    .font(.title2.bold())
                Text("Only the display label changes. The validated Wine/GPTK payload remains read-only.")
                    .foregroundStyle(.secondary)
            }
            TextField("Runtime name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Text("\(name.trimmingCharacters(in: .whitespacesAndNewlines).count)/80")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidName)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var isValidName: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty
            && value.count <= 80
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private func save() {
        guard isValidName else { return }
        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
