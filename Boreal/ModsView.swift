import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ModsView: View {
    private enum Tab: String, CaseIterable {
        case mods
        case plugins
    }

    private enum ModFilter: Hashable {
        case all
        case enabled
        case disabled
        case conflicts
        case content(ModContentType)

        var title: String {
            switch self {
            case .all: "All Mods"
            case .enabled: "Enabled"
            case .disabled: "Disabled"
            case .conflicts: "Conflicts"
            case .content(let type): type.displayName
            }
        }

        var symbol: String {
            switch self {
            case .all: "shippingbox"
            case .enabled: "checkmark.circle"
            case .disabled: "circle"
            case .conflicts: "exclamationmark.triangle"
            case .content(let type):
                switch type {
                case .modLoader: "shippingbox"
                case .asiPlugin: "puzzlepiece.extension"
                case .cleo: "curlybraces.square"
                case .coreComponent: "gearshape.2"
                case .rootOverlay: "folder"
                case .unrealPak: "shippingbox.fill"
                case .config: "slider.horizontal.3"
                case .dragonAgeOverride: "folder.badge.gearshape"
                case .dragonAgeDazip: "archivebox"
                case .witcher2CookedPC: "folder"
                case .witcher2UserContent: "person.crop.folder"
                case .manual: "hand.raised"
                case .unknown: "questionmark.square"
                }
            }
        }
    }

    private enum ModSort: String, CaseIterable, Identifiable {
        case priority
        case name
        case recentlyInstalled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .priority: "Priority"
            case .name: "Name"
            case .recentlyInstalled: "Recently installed"
            }
        }
    }

    @Environment(BorealStore.self) private var store
    let game: StoreLibraryGame
    @State private var tab: Tab = .mods
    @State private var showsImporter = false
    @State private var installPreview: ModInstallPreview?
    @State private var showsNewProfile = false
    @State private var newProfileName = ""
    @State private var modToRemove: InstalledMod?
    @State private var searchText = ""
    @State private var selectedFilter: ModFilter = .all
    @State private var sort = ModSort.priority
    @State private var selectedModIDs = Set<UUID>()
    @State private var versionDraft = ""

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
            selectedModIDs = []
            selectedFilter = .all
            searchText = ""
            sort = .priority
            versionDraft = ""
            store.refreshMods(for: game)
        }
        .onChange(of: store.modState(for: game)?.mods.map(\.id) ?? []) { _, _ in
            synchronizeSelection()
        }
        .onChange(of: selectedFilter) { _, _ in
            synchronizeSelection()
        }
        .onChange(of: searchText) { _, _ in
            synchronizeSelection()
        }
        .onChange(of: selectedModIDs) { _, _ in
            synchronizeVersionDraft()
        }
        .onChange(of: store.modState(for: game)?.profileID) { _, _ in
            synchronizeVersionDraft()
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
                Text("Mods")
                    .font(.title2.weight(.semibold))
                Text(isUnsupportedDefinitiveEdition
                    ? "Definitive Edition detected; a verified mod runtime is not available."
                    : "Manage modifications for \(game.name). Stage changes safely, then deploy them to the game.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isUnsupportedDefinitiveEdition {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search mods…", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 190)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.10))
                }
            }
            Button("Import Mod…", systemImage: "arrow.down.to.line") {
                showsImporter = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                isUnsupportedDefinitiveEdition
                    || state == nil
                    || store.isModOperationActive(for: game)
            )
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
                                : state.adapter == .witcher2
                                    ? "Witcher 2 roots synchronized"
                                : "Plugins \(health.pluginsSynchronized ? "synchronized" : "out of sync")",
                            symbol: state.adapter == .gtaSanAndreas || state.adapter == .gtaSanAndreasDefinitiveEdition
                                ? "shippingbox"
                                : state.adapter == .witcher2 ? "folder" : "list.number"
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
        let visibleMods = filteredMods(from: state)

        return HStack(alignment: .top, spacing: 12) {
            modFilterSidebar(state)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Modifications")
                        .font(.headline)
                    Text("\(visibleMods.count) of \(state.mods.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("Lower rows win conflicts", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(ModSort.allCases) { value in
                            Button {
                                sort = value
                            } label: {
                                Label(value.title, systemImage: sort == value ? "checkmark" : "arrow.up.arrow.down")
                            }
                        }
                    } label: {
                        Label("Sort: \(sort.title)", systemImage: "arrow.up.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if visibleMods.isEmpty {
                    ContentUnavailableView(
                        state.mods.isEmpty ? "No mods installed" : "No mods match this filter",
                        systemImage: state.mods.isEmpty ? "shippingbox" : "line.3.horizontal.decrease.circle",
                        description: Text(state.mods.isEmpty
                            ? "Import a GTA SA:DE .pak file, ZIP, RAR, 7z or Dragon Age DAZIP archive to add its files to the mod profile."
                            : "Try another filter or search term.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    modTable(visibleMods, state: state)
                }
            }
            .frame(minWidth: 450, maxWidth: .infinity, alignment: .topLeading)

            if let selectedMod = selectedMod(in: state) {
                modDetails(selectedMod, state: state)
            } else {
                modDetailsPlaceholder
            }
        }
        .onAppear { synchronizeSelection() }
        .onChange(of: visibleMods.map(\.id)) { _, _ in synchronizeSelection() }
    }

    private func modFilterSidebar(_ state: ModGameState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            filterButton(.all, count: state.mods.count)
            filterButton(.enabled, count: state.mods.filter(\.enabled).count)
            filterButton(.disabled, count: state.mods.filter { !$0.enabled }.count)
            filterButton(.conflicts, count: conflictedModIDs(in: state).count)

            Divider()
                .padding(.vertical, 8)

            Text("Content type")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(ModContentType.allCases.filter { type in
                state.mods.contains { $0.contentType == type }
            }, id: \.self) { type in
                filterButton(.content(type), count: state.mods.filter { $0.contentType == type }.count)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minWidth: 170, idealWidth: 170, maxWidth: 170, minHeight: 360, maxHeight: 520, alignment: .topLeading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }

    private func filterButton(_ filter: ModFilter, count: Int) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 9) {
                Image(systemName: filter.symbol)
                    .frame(width: 16)
                Text(filter.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(selectedFilter == filter ? .white.opacity(0.75) : .secondary)
            }
            .font(.callout)
            .foregroundStyle(selectedFilter == filter ? .white : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(selectedFilter == filter ? Color.accentColor.opacity(0.72) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && selectedFilter != filter)
    }

    private func modTable(_ mods: [InstalledMod], state: ModGameState) -> some View {
        Table(of: InstalledMod.self, selection: $selectedModIDs) {
            TableColumn("Priority", content: { (mod: InstalledMod) in
                Text("\(mod.priority + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            })
            .width(min: 54, ideal: 60, max: 70)

            TableColumn("Modification", content: { (mod: InstalledMod) in
                HStack(spacing: 9) {
                    Image(systemName: mod.contentType == .unknown ? "shippingbox" : ModFilter.content(mod.contentType).symbol)
                        .foregroundStyle(mod.enabled ? Color.accentColor : .secondary)
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mod.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if mod.isExternallyDetected {
                            Text("Detected outside Boreal")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if !mod.requirements.isEmpty {
                            Text("Requires \(mod.requirements.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                    }
                }
                .contextMenu {
                    Button("Move Up", systemImage: "arrow.up") {
                        moveMod(mod, direction: -1, state: state)
                    }
                    .disabled(mod.isExternallyDetected)
                    Button("Move Down", systemImage: "arrow.down") {
                        moveMod(mod, direction: 1, state: state)
                    }
                    .disabled(mod.isExternallyDetected)
                    Divider()
                    Button("Open Files", systemImage: "folder") {
                        store.openModFiles(mod.id, for: game)
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        modToRemove = mod
                    }
                    .disabled(mod.isExternallyDetected)
                }
            })
            .width(min: 220, ideal: 280)

            TableColumn("Version", content: { (mod: InstalledMod) in
                Text(mod.version ?? "—")
                    .font(.caption)
                    .foregroundStyle(mod.version == nil ? .tertiary : .secondary)
            })
            .width(min: 65, ideal: 80, max: 110)

            TableColumn("Type", content: { (mod: InstalledMod) in
                Text(mod.contentType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            })
            .width(min: 105, ideal: 125, max: 160)

            TableColumn("Files", content: { (mod: InstalledMod) in
                Text("\(mod.files.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            })
            .width(min: 48, ideal: 58, max: 70)

            TableColumn("Installed", content: { (mod: InstalledMod) in
                Text(mod.isExternallyDetected
                    ? "Detected"
                    : mod.installedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            })
            .width(min: 120, ideal: 145, max: 180)

            TableColumn("Status", content: { (mod: InstalledMod) in
                let conflicts = state.conflicts.filter { $0.modIDs.contains(mod.id) }.count
                Label(
                    conflicts == 0 ? "Ready" : "\(conflicts) conflict\(conflicts == 1 ? "" : "s")",
                    systemImage: conflicts == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(conflicts == 0 ? .green : .orange)
                .lineLimit(1)
            })
            .width(min: 82, ideal: 105, max: 125)

            TableColumn("Enabled", content: { (mod: InstalledMod) in
                Toggle("", isOn: enabledBinding(for: mod))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(mod.isExternallyDetected || store.isModOperationActive(for: game))
            })
            .width(min: 68, ideal: 74, max: 85)
        } rows: {
            ForEach(mods) { mod in
                TableRow(mod)
            }
        }
        .tableStyle(.inset)
        .frame(minHeight: 360, idealHeight: 450, maxHeight: 520)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }

    private func modDetails(_ mod: InstalledMod, state: ModGameState) -> some View {
        let conflicts = state.conflicts.filter { $0.modIDs.contains(mod.id) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.68), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mod.name)
                            .font(.headline)
                            .lineLimit(2)
                        Label(mod.enabled ? "Enabled" : "Disabled", systemImage: mod.enabled ? "checkmark.circle.fill" : "pause.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(mod.enabled ? .green : .secondary)
                    }
                }

                Toggle("Enabled", isOn: enabledBinding(for: mod))
                    .toggleStyle(.switch)
                    .disabled(mod.isExternallyDetected || store.isModOperationActive(for: game))

                Divider()

                DetailRow(title: "Source", value: mod.installationSource.displayName, symbol: "externaldrive")
                modVersionEditor(for: mod)
                DetailRow(title: "Content", value: mod.contentType.displayName, symbol: "square.stack.3d.up")
                DetailRow(title: "Deployment", value: mod.deployStrategy.displayName, symbol: "arrow.down.app")
                DetailRow(title: "Files", value: "\(mod.files.count)", symbol: "doc.on.doc")
                if !mod.plugins.isEmpty {
                    DetailRow(title: "Plugins", value: "\(mod.plugins.count)", symbol: "list.number")
                }
                if let archive = mod.archiveRelativePath {
                    DetailRow(title: "Archive", value: archive, symbol: "archivebox")
                }
                DetailRow(
                    title: mod.isExternallyDetected ? "Detected" : "Installed",
                    value: mod.isExternallyDetected ? "In the installed game files" : mod.installedAt.formatted(date: .abbreviated, time: .shortened),
                    symbol: mod.isExternallyDetected ? "externaldrive" : "calendar"
                )

                if !mod.requirements.isEmpty {
                    detailList(title: "Requirements", values: mod.requirements, symbol: "link", tint: .orange)
                }
                if !mod.warnings.isEmpty {
                    detailList(title: "Warnings", values: mod.warnings, symbol: "exclamationmark.triangle.fill", tint: .orange)
                }
                if !conflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Conflicts (\(conflicts.count))", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        ForEach(conflicts.prefix(4)) { conflict in
                            Text(conflict.relativePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if conflicts.count > 4 {
                            Text("and \(conflicts.count - 4) more…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    Button("Open Files", systemImage: "folder") {
                        store.openModFiles(mod.id, for: game)
                    }
                    .buttonStyle(.bordered)
                    .disabled(mod.isExternallyDetected || store.isModOperationActive(for: game))
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        modToRemove = mod
                    }
                    .buttonStyle(.bordered)
                    .disabled(mod.isExternallyDetected || store.isModOperationActive(for: game))
                }
            }
            .padding(15)
        }
        .frame(minWidth: 270, idealWidth: 270, maxWidth: 270, minHeight: 360, maxHeight: 520, alignment: .topLeading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }

    private var modDetailsPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Select a mod")
                .font(.headline)
            Text("Choose a row to inspect its files, status and deployment details.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(minWidth: 270, idealWidth: 270, maxWidth: 270, minHeight: 360, maxHeight: 520)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }

    private func detailList(title: String, values: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func modVersionEditor(for mod: InstalledMod) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Version", systemImage: "number")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("e.g. 1.0.0", text: $versionDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(mod.isExternallyDetected || store.isModOperationActive(for: game))
                    .onSubmit { saveVersion(for: mod) }

                Button("Save") {
                    saveVersion(for: mod)
                }
                .buttonStyle(.bordered)
                .disabled(mod.isExternallyDetected || store.isModOperationActive(for: game))

                if mod.version != nil || !versionDraft.isEmpty {
                    Button("Clear") {
                        versionDraft = ""
                        store.setModVersion(nil, modID: mod.id, for: game)
                    }
                    .buttonStyle(.borderless)
                    .disabled(mod.isExternallyDetected || store.isModOperationActive(for: game))
                }
            }

            if mod.isExternallyDetected {
                Text("External mods are read-only in Boreal.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Enter the release version manually, for example 1.2.0 or SA:DE 1.0.6.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveVersion(for mod: InstalledMod) {
        let normalized = versionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        versionDraft = normalized
        store.setModVersion(normalized.isEmpty ? nil : normalized, modID: mod.id, for: game)
    }

    private func filteredMods(from state: ModGameState) -> [InstalledMod] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let conflictIDs = conflictedModIDs(in: state)
        let filtered = state.mods.filter { mod in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .enabled: matchesFilter = mod.enabled
            case .disabled: matchesFilter = !mod.enabled
            case .conflicts: matchesFilter = conflictIDs.contains(mod.id)
            case .content(let type): matchesFilter = mod.contentType == type
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return mod.name.localizedCaseInsensitiveContains(query)
                || mod.contentType.displayName.localizedCaseInsensitiveContains(query)
                || mod.deployStrategy.displayName.localizedCaseInsensitiveContains(query)
                || mod.version?.localizedCaseInsensitiveContains(query) == true
        }

        switch sort {
        case .priority:
            return filtered.sorted { $0.priority < $1.priority }
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyInstalled:
            return filtered.sorted { $0.installedAt > $1.installedAt }
        }
    }

    private func selectedMod(in state: ModGameState) -> InstalledMod? {
        guard let id = selectedModIDs.first else { return nil }
        return state.mods.first { $0.id == id }
    }

    private func conflictedModIDs(in state: ModGameState) -> Set<UUID> {
        Set(state.conflicts.flatMap(\.modIDs))
    }

    private func enabledBinding(for mod: InstalledMod) -> Binding<Bool> {
        Binding(
            get: { store.modState(for: game)?.mods.first(where: { $0.id == mod.id })?.enabled ?? mod.enabled },
            set: { store.setModEnabled($0, modID: mod.id, for: game) }
        )
    }

    private func synchronizeSelection() {
        guard let state = store.modState(for: game) else {
            selectedModIDs = []
            return
        }
        let visibleIDs = Set(filteredMods(from: state).map(\.id))
        selectedModIDs = selectedModIDs.intersection(visibleIDs)
        if selectedModIDs.isEmpty, let first = filteredMods(from: state).first {
            selectedModIDs = [first.id]
        }
        synchronizeVersionDraft()
    }

    private func synchronizeVersionDraft() {
        guard let state = store.modState(for: game),
              let selectedMod = selectedMod(in: state) else {
            versionDraft = ""
            return
        }
        versionDraft = selectedMod.version ?? ""
    }

    private func moveMod(_ mod: InstalledMod, direction: Int, state: ModGameState) {
        guard !store.isModOperationActive(for: game) else { return }
        let ordered = state.mods.sorted { $0.priority < $1.priority }
        guard let index = ordered.firstIndex(where: { $0.id == mod.id }) else { return }
        if direction < 0 {
            guard index > 0 else { return }
            store.moveMod(from: IndexSet(integer: index), to: index, for: game)
        } else {
            guard index < ordered.count - 1 else { return }
            store.moveMod(from: IndexSet(integer: index), to: index + 2, for: game)
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

    private static var archiveTypes: [UTType] {
        [
            .archive,
            UTType(filenameExtension: "zip") ?? .archive,
            UTType(filenameExtension: "7z") ?? .archive,
            UTType(filenameExtension: "rar") ?? .archive,
            UTType(filenameExtension: "dazip") ?? .archive,
            UTType(filenameExtension: "dzip") ?? .data,
            UTType(filenameExtension: "pak") ?? .data
        ]
    }

    private func isGTAAdapter(_ adapter: ModGameAdapter) -> Bool {
        adapter == .gtaSanAndreas || adapter == .gtaSanAndreasDefinitiveEdition
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
                Text(preview.isUpdate ? "Update Mod" : "Install Mod")
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
                    previewRow(
                        "Archive",
                        value: preview.adapter == .dragonAgeOrigins
                            && preview.archiveName.lowercased().hasSuffix(".dazip")
                            ? "DAZIP"
                            : preview.format.rawValue.uppercased()
                    )
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

            if preview.isUpdate {
                Label(
                    "An installed mod with the same name will be replaced. Its UUID, load order and enabled state will be kept.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.callout)
                .foregroundStyle(.blue)
            }

            Group {
                if preview.adapter == .gtaSanAndreasDefinitiveEdition {
                    Text(preview.format == .loosePak
                        ? "Boreal will keep the .pak in its mod library, stage it safely and deploy it to the GTA SA:DE ~mods folder."
                        : "Boreal will keep the archive in its mod library, stage its PAK files safely and deploy them to the GTA SA:DE ~mods folder.")
                } else if preview.isUpdate {
                    Text("Boreal will replace the staged files and automatically deploy the updated mod to the game.")
                } else {
                    Text("Boreal will keep the archive in its mod library and stage the files separately. Nothing is copied into the game until you choose Deploy Changes.")
                }
            }
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button(preview.isUpdate ? "Update" : "Install", action: onInstall)
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
