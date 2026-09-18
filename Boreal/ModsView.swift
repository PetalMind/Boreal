import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ModsView: View {
    private enum Tab: String, CaseIterable {
        case mods
        case plugins
    }

    @Environment(BorealStore.self) private var store
    let game: StoreLibraryGame
    @State private var tab: Tab = .mods
    @State private var showsImporter = false
    @State private var installPreview: ModInstallPreview?
    @State private var showsNewProfile = false
    @State private var newProfileName = ""
    @State private var modToRemove: InstalledMod?

    private var state: ModGameState? { store.modState(for: game) }
    private var isUnsupportedDefinitiveEdition: Bool {
        GTASAModLoaderAdapter.isDefinitiveEdition(game: game) && !store.supportsMods(for: game)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if isUnsupportedDefinitiveEdition {
                definitiveEditionNotice
            } else if let state {
                profileControls(state)
                if state.adapter == .gtaSanAndreas, let runtime = state.runtime {
                    gtaRuntime(runtime)
                }
                deploymentHealth(state)
                summary(state)
                if state.adapter == .skyrimSpecialEdition {
                    Picker("Mod content", selection: $tab) {
                        Text("Mods").tag(Tab.mods)
                        Text("Plugins").tag(Tab.plugins)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

                if state.pendingChanges {
                    pendingChanges
                }

                if isGTAAdapter(state.adapter) {
                    modsList(state)
                } else {
                    switch tab {
                    case .mods:
                        modsList(state)
                    case .plugins:
                        pluginsList(state)
                    }
                }
            } else if store.isModOperationActive(for: game) {
                ProgressView("Preparing mod library…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ContentUnavailableView(
                    "Mods unavailable",
                    systemImage: "shippingbox",
                    description: Text("The installed game folder is not available right now.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .padding(22)
        .task(id: game.id) {
            store.refreshMods(for: game)
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: Self.archiveTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { @MainActor in
                installPreview = await store.inspectModArchive(url, for: game)
            }
        }
        .sheet(item: $installPreview) { preview in
            ModInstallPreviewSheet(
                preview: preview,
                onCancel: {
                    store.discardModInstallPreview(preview)
                    installPreview = nil
                },
                onInstall: {
                    store.installMod(preview, for: game)
                    installPreview = nil
                }
            )
            .frame(minWidth: 460, minHeight: 390)
        }
        .alert("New mod profile", isPresented: $showsNewProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Create") {
                let name = newProfileName
                newProfileName = ""
                store.createModProfile(named: name, for: game)
            }
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
        } message: {
            Text("The new profile reuses the existing mod library and starts with the current staged selection.")
        }
        .alert("Remove mod?", isPresented: Binding(
            get: { modToRemove != nil },
            set: { if !$0 { modToRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let modToRemove {
                    store.removeMod(modToRemove.id, for: game)
                }
                modToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                modToRemove = nil
            }
        } message: {
            Text("\(modToRemove?.name ?? "This mod") will be removed from the Boreal library. Already deployed files remain until you deploy the updated profile.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.title2.weight(.semibold))
                Text(isUnsupportedDefinitiveEdition
                    ? "Definitive Edition detected; a verified mod runtime is not available."
                    : GTASADefinitiveEditionAdapter.supports(game: game)
                        ? "Manage CLEO Redux and Unreal Engine .pak mods for the Definitive Edition."
                        : GTASAModLoaderAdapter.supports(game: game)
                            ? "Manage GTA San Andreas mods through a controlled Mod Loader profile."
                            : "Stage files outside the game, review conflicts, then deploy one controlled profile.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Install Mod…", systemImage: "plus") {
                showsImporter = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUnsupportedDefinitiveEdition || store.isModOperationActive(for: game))
        }
    }

    private var definitiveEditionNotice: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Definitive Edition mod runtime unavailable")
                        .font(.headline)
                    Text("This installation is the Unreal Engine Definitive Edition. The manager described for classic GTA San Andreas uses ASI Loader and San Andreas Mod Loader, which are not verified for this executable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Label("Classic GTA SA / Enhanced Edition management is available only when Boreal detects gta_sa.exe and a compatible Mod Loader runtime.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                if let installation = store.installedLocation(for: game) {
                    Button("Open Game Files", systemImage: "folder") {
                        NSWorkspace.shared.open(installation)
                    }
                }
                Spacer()
                Text("No files were copied or changed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.orange.opacity(0.25))
        }
    }

    private func gtaRuntime(_ runtime: ModRuntimeState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: runtime.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(runtime.isReady ? .green : .orange)
                Text("Modding Runtime")
                    .font(.headline)
                Spacer()
                Button("Repair Modding Runtime", systemImage: "wrench.and.screwdriver") {
                    store.repairModdingRuntime(for: game)
                }
                .buttonStyle(.bordered)
                .disabled(store.isModOperationActive(for: game))
            }
            HStack(spacing: 14) {
                runtimeItem("ASI Loader", installed: runtime.asiLoaderInstalled)
                runtimeItem("GTA SA Mod Loader", installed: runtime.modLoaderInstalled)
                runtimeItem("CLEO", installed: runtime.cleoInstalled)
                Spacer()
            }
            Text(runtime.compatibility.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(runtime.isReady ? .green : .orange)
            if let executableHash = runtime.executableHash {
                Text("Executable SHA-256: \(executableHash.prefix(12))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if runtime.executableVersion == nil, runtime.executablePath != nil {
                Text("The executable version is not verified. Mod Loader compatibility is primarily documented for GTA SA 1.0 US/EU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if runtime.executablePath == nil {
                Text("Boreal could not locate gta_sa.exe in the installed game folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !runtime.asiLoaderInstalled || !runtime.modLoaderInstalled {
                Text("Repair prepares Boreal-owned folders, but does not invent or download missing ASI Loader/Mod Loader binaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background((runtime.isReady ? Color.green : Color.orange).opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke((runtime.isReady ? Color.green : Color.orange).opacity(0.22))
        }
    }

    private func runtimeItem(_ title: String, installed: Bool) -> some View {
        Label(title, systemImage: installed ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(installed ? .green : .secondary)
    }

    private func profileControls(_ state: ModGameState) -> some View {
        HStack(spacing: 10) {
            Label("Profile", systemImage: "person.crop.square")
                .foregroundStyle(.secondary)
            Picker("Profile", selection: Binding(
                get: { store.modState(for: game)?.profileID ?? state.profileID },
                set: { store.switchModProfile(to: $0, for: game) }
            )) {
                ForEach(store.modProfiles(for: game)) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            Button("New Profile", systemImage: "plus") {
                showsNewProfile = true
            }
            .buttonStyle(.bordered)
            .disabled(store.isModOperationActive(for: game))
            Spacer()
        }
    }

    private func deploymentHealth(_ state: ModGameState) -> some View {
        let health = store.modDeploymentHealth(for: game)
        return Group {
            if let health {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Image(systemName: health.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(health.needsAttention ? .orange : .green)
                        Text(health.needsAttention ? "Deployment needs attention" : "Mod Deployment")
                            .font(.headline)
                        Spacer()
                        if health.pendingChanges {
                            Text("Deployment pending")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    HStack(spacing: 16) {
                        healthItem("\(health.deployedModCount) mods deployed", symbol: "shippingbox")
                        healthItem("\(health.managedFileCount) managed files", symbol: "doc.on.doc")
                        healthItem(
                            state.adapter == .gtaSanAndreas
                                ? "Mod Loader profile synchronized"
                                : state.adapter == .gtaSanAndreasDefinitiveEdition
                                    ? "Pak profile synchronized"
                                : "Plugins \(health.pluginsSynchronized ? "synchronized" : "out of sync")",
                            symbol: state.adapter == .gtaSanAndreas || state.adapter == .gtaSanAndreasDefinitiveEdition
                                ? "shippingbox"
                                : "list.number"
                        )
                        healthItem("Vanilla \(health.vanillaFilesProtected ? "protected" : "at risk")", symbol: "lock.shield")
                    }
                    if !health.externalChanges.isEmpty {
                        Text("\(health.externalChanges.count) managed files changed externally")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !health.validation.missingMasters.isEmpty {
                        Text("\(health.validation.missingMasters.count) plugin dependencies are missing or disabled")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if health.validation.exceedsFullPluginLimit || health.validation.exceedsLightPluginLimit {
                        Text("Plugin limit exceeded — deployment is blocked")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        if let lastDeployment = health.lastDeployment {
                            Text("Last deployment \(lastDeployment.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if health.needsAttention {
                            Button("Review Problems") {
                                tab = isGTAAdapter(state.adapter) ? .mods : .plugins
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(13)
                .background((health.needsAttention ? Color.orange : Color.green).opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke((health.needsAttention ? Color.orange : Color.green).opacity(0.22))
                }
            }
        }
    }

    private func healthItem(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func summary(_ state: ModGameState) -> some View {
        HStack(spacing: 10) {
            ModSummaryCard(title: "Installed", value: "\(state.mods.count)", symbol: "shippingbox")
            ModSummaryCard(title: "Active", value: "\(state.activeModCount)", symbol: "checkmark.circle")
            ModSummaryCard(title: "Conflicts", value: "\(state.conflictCount)", symbol: "exclamationmark.triangle", tint: state.conflictCount == 0 ? .green : .orange)
            if isGTAAdapter(state.adapter) {
                let size = state.mods.reduce(Int64(0)) { total, mod in total + mod.files.reduce(0) { $0 + $1.size } }
                ModSummaryCard(title: "Staged size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file), symbol: "externaldrive")
            }
            Spacer()
        }
    }

    private var pendingChanges: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.dotted")
                .foregroundStyle(.orange)
            Text("Changes are staged and have not been copied into the game yet.")
                .font(.callout)
            Spacer()
            Button("Deploy Changes", systemImage: "arrow.down.app") {
                store.deployMods(for: game)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isModOperationActive(for: game))
        }
        .padding(12)
        .background(.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.orange.opacity(0.25)) }
    }

    private func modsList(_ state: ModGameState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.mods.isEmpty {
                ContentUnavailableView(
                    "No mods installed",
                    systemImage: "shippingbox",
                    description: Text("Install a ZIP, RAR or 7z archive to add its files to the staged profile.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    Section("File priority — later rows win conflicts") {
                        ForEach(state.mods.sorted { $0.priority < $1.priority }) { mod in
                            ModRow(
                                mod: mod,
                                conflictCount: state.conflicts.filter { $0.modIDs.contains(mod.id) }.count,
                                isBusy: store.isModOperationActive(for: game),
                                adapter: state.adapter,
                                onOpenFiles: { store.openModFiles(mod.id, for: game) },
                                onRemove: { modToRemove = mod },
                                enabled: Binding(
                                    get: { store.modState(for: game)?.mods.first(where: { $0.id == mod.id })?.enabled ?? mod.enabled },
                                    set: { store.setModEnabled($0, modID: mod.id, for: game) }
                                )
                            )
                        }
                        .onMove { offsets, destination in
                            store.moveMod(from: offsets, to: destination, for: game)
                        }
                    }
                    if !state.conflicts.isEmpty {
                        Section("Conflicts") {
                            ForEach(state.conflicts) { conflict in
                                conflictRow(conflict, state: state)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            }
        }
    }

    private func pluginsList(_ state: ModGameState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plugin load order is independent from file priority. Boreal writes the enabled order to Skyrim’s plugins.txt during deployment; the profile remains the source of truth.")
                .font(.callout)
                .foregroundStyle(.secondary)
            pluginLimits(state.validation)
            if !state.validation.missingMasters.isEmpty || !state.validation.invalidPluginHeaders.isEmpty {
                validationProblems(state.validation)
            }
            if state.plugins.isEmpty {
                ContentUnavailableView("No plugins detected", systemImage: "list.number")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    Section("Manual load order") {
                        ForEach(state.plugins.sorted { $0.loadOrder < $1.loadOrder }) { plugin in
                            PluginRow(
                                plugin: plugin,
                                isBusy: store.isModOperationActive(for: game),
                                enabled: Binding(
                                    get: { store.modState(for: game)?.plugins.first(where: { $0.id == plugin.id })?.enabled ?? plugin.enabled },
                                    set: { store.setPluginEnabled($0, pluginID: plugin.id, for: game) }
                                )
                            )
                        }
                        .onMove { offsets, destination in
                            store.movePlugin(from: offsets, to: destination, for: game)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            }
        }
    }

    private func pluginLimits(_ validation: ModValidationReport) -> some View {
        HStack(spacing: 14) {
            Label("Full \(validation.fullPluginCount) / \(ModValidationReport.fullPluginLimit)", systemImage: "square.stack.3d.up")
                .foregroundStyle(validation.exceedsFullPluginLimit ? .red : .secondary)
            Label("Light \(validation.lightPluginCount) / \(ModValidationReport.lightPluginLimit)", systemImage: "square.stack.3d.up.fill")
                .foregroundStyle(validation.exceedsLightPluginLimit ? .red : .secondary)
        }
        .font(.caption.weight(.medium))
    }

    private func validationProblems(_ validation: ModValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !validation.missingMasters.isEmpty {
                Label("Missing masters", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                ForEach(validation.missingMasters) { item in
                    Text("\(item.plugin) requires \(item.master)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if !validation.invalidPluginHeaders.isEmpty {
                Label("Unreadable plugin headers", systemImage: "doc questionmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(validation.invalidPluginHeaders.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func conflictRow(_ conflict: ModConflict, state: ModGameState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(conflict.kind == .directReplacement ? .red : conflict.kind == .mergeable ? .blue : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(conflict.relativePath)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                let winner = state.mods.first(where: { $0.id == conflict.winnerModID })?.name ?? "Unknown mod"
                Text("\(conflict.kind.displayName) · Winner: \(winner) · \(conflict.overriddenModIDs.count) overridden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private static var archiveTypes: [UTType] {
        [.archive, UTType(filenameExtension: "zip") ?? .archive, UTType(filenameExtension: "7z") ?? .archive, UTType(filenameExtension: "rar") ?? .archive]
    }

    private func isGTAAdapter(_ adapter: ModGameAdapter) -> Bool {
        adapter == .gtaSanAndreas || adapter == .gtaSanAndreasDefinitiveEdition
    }
}

private struct ModSummaryCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ModRow: View {
    let mod: InstalledMod
    let conflictCount: Int
    let isBusy: Bool
    let adapter: ModGameAdapter
    let onOpenFiles: () -> Void
    let onRemove: () -> Void
    @Binding var enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $enabled)
                .labelsHidden()
                .disabled(isBusy)
            Text("\(mod.priority + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(mod.name).font(.body.weight(.medium))
                HStack(spacing: 8) {
                    if adapter == .gtaSanAndreas || adapter == .gtaSanAndreasDefinitiveEdition {
                        Text(mod.contentType.displayName)
                        Text(mod.deployStrategy.displayName)
                    }
                    Text("\(mod.files.count) files")
                    if !mod.plugins.isEmpty { Text("\(mod.plugins.count) plugins") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if conflictCount > 0 {
                Label("\(conflictCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .help("Files shared with another active mod")
            }
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to change file priority")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Open Files", systemImage: "folder") {
                onOpenFiles()
            }
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) {
                onRemove()
            }
        }
    }
}

private struct PluginRow: View {
    let plugin: BethesdaPlugin
    let isBusy: Bool
    @Binding var enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $enabled)
                .labelsHidden()
                .disabled(isBusy)
            Text("\(plugin.loadOrder + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.filename).font(.body.monospaced())
                Text(plugin.modID == nil ? "Game plugin · \(plugin.displayType)" : plugin.displayType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !plugin.masters.isEmpty {
                Label("\(plugin.masters.count) masters", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to change plugin load order")
        }
        .padding(.vertical, 3)
    }
}

private struct ModInstallPreviewSheet: View {
    let preview: ModInstallPreview
    let onCancel: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Install Mod")
                    .font(.title2.weight(.semibold))
                Text(preview.archiveName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            GroupBox("Detected structure") {
                VStack(alignment: .leading, spacing: 11) {
                    Label("\(preview.adapter.displayName) · \(preview.contentType.displayName)", systemImage: preview.canInstallAutomatically ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(preview.canInstallAutomatically ? .green : .orange)
                    previewRow("Files", value: "\(preview.fileCount)")
                    previewRow("Plugins", value: "\(preview.pluginCount)")
                    previewRow("Deployment", value: preview.deployStrategy.displayName)
                    previewRow("Archive", value: preview.format.rawValue.uppercased())
                    previewRow("Installation root", value: "/\(preview.detectedRoot)")
                    if preview.totalSize > 0 {
                        previewRow("Size", value: ByteCountFormatter.string(fromByteCount: preview.totalSize, countStyle: .file))
                    }
                }
                .padding(.vertical, 5)
            }

            if !preview.requirements.isEmpty {
                Label("Requires: \(preview.requirements.joined(separator: ", "))", systemImage: "link")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(preview.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Text("Boreal will keep the archive in its mod library and stage the files separately. Nothing is copied into the game until you choose Deploy Changes.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .disabled(!preview.canInstallAutomatically)
            }
        }
        .padding(24)
    }

    private func previewRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospaced())
        }
    }
}
