import AppKit
import SwiftUI

struct EnvironmentInspectorView: View {
    @Environment(BorealStore.self) private var store
    let application: WindowsApplication
    @State private var resolution: CompatibilityResolution?
    @State private var dependencies: [DependencyRequirement] = []
    @State private var diagnosis: LaunchFailureDiagnosis?
    @State private var copiedDiagnostics = false
    @State private var reportMessage: String?
    @State private var snapshots: [EnvironmentSnapshot] = []
    @State private var snapshotToRestore: EnvironmentSnapshot?
    @State private var snapshotToDelete: EnvironmentSnapshot?
    @State private var confirmsCacheClear = false
    @State private var confirmsRepair = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    inspectorHeader
                    if let resolution {
                        compatibilityCard(resolution)
                    } else {
                        loadingCard("Analyzing executable, prefix and runtime…")
                    }
                    dependencyCard
                    snapshotCard
                    if let diagnosis {
                        diagnosisCard(diagnosis)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Environment Inspector")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(copiedDiagnostics ? "Copied" : "Copy Diagnostics", systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc") {
                        Task {
                            guard let value = await store.copyDiagnostics(for: application.id) else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(value, forType: .string)
                            copiedDiagnostics = true
                        }
                    }
                    Button("Save Report", systemImage: "doc.badge.plus") {
                        Task {
                            do {
                                let report = try await store.saveCompatibilityReport(for: application.id)
                                reportMessage = "Saved report \(report.traceID.shortValue)."
                            } catch {
                                reportMessage = error.localizedDescription
                            }
                        }
                    }
                    Button("Clear Shader Cache", systemImage: "sparkles") {
                        confirmsCacheClear = true
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 560)
        .task { await refresh() }
        .alert("Compatibility report", isPresented: Binding(get: { reportMessage != nil }, set: { if !$0 { reportMessage = nil } })) {
            Button("OK", role: .cancel) { reportMessage = nil }
        } message: {
            Text(reportMessage ?? "")
        }
        .confirmationDialog("Clear shader cache?", isPresented: $confirmsCacheClear) {
            Button("Clear Cache", role: .destructive) {
                Task {
                    do {
                        let count = try await store.clearShaderCache(for: application.id)
                        reportMessage = count == 0 ? "No safe shader cache locations were found." : "Cleared \(count) safe shader cache location(s)."
                    } catch {
                        reportMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Shaders will be rebuilt on a later launch and the first run may stutter temporarily.")
        }
        .confirmationDialog("Install missing dependencies?", isPresented: $confirmsRepair) {
            Button("Install", role: .destructive) {
                Task {
                    do {
                        try await store.repairLastLaunchFailure(for: application.id)
                        await refresh()
                        reportMessage = "The missing dependencies were installed into a new recovery point."
                    } catch {
                        reportMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Boreal will snapshot the environment, then install only dependencies identified by static evidence or an explicit required profile entry.")
        }
        .confirmationDialog("Restore environment snapshot?", isPresented: Binding(get: { snapshotToRestore != nil }, set: { if !$0 { snapshotToRestore = nil } })) {
            Button("Restore", role: .destructive) {
                guard let snapshotToRestore else { return }
                Task {
                    do {
                        try await store.restoreEnvironmentSnapshot(snapshotToRestore, environmentID: application.environmentID)
                        snapshots = await store.environmentSnapshots(for: application.environmentID)
                        reportMessage = "Environment snapshot restored."
                    } catch {
                        reportMessage = error.localizedDescription
                    }
                    self.snapshotToRestore = nil
                }
            }
            Button("Cancel", role: .cancel) { snapshotToRestore = nil }
        } message: {
            Text("The current environment is preserved as a new snapshot before restore when possible.")
        }
        .confirmationDialog("Delete environment snapshot?", isPresented: Binding(get: { snapshotToDelete != nil }, set: { if !$0 { snapshotToDelete = nil } })) {
            Button("Delete Snapshot", role: .destructive) {
                guard let snapshotToDelete else { return }
                Task {
                    do {
                        try await store.deleteEnvironmentSnapshot(snapshotToDelete)
                        snapshots = await store.environmentSnapshots(for: application.environmentID)
                    } catch {
                        reportMessage = error.localizedDescription
                    }
                    self.snapshotToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { snapshotToDelete = nil }
        }
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(application.name, systemImage: application.iconSymbol)
                .font(.title2.weight(.semibold))
            Text("Evidence-backed state for the selected executable and its managed Windows environment.")
                .foregroundStyle(.secondary)
        }
    }

    private func compatibilityCard(_ value: CompatibilityResolution) -> some View {
        InspectorCard(title: "Compatibility resolution", symbol: "checkmark.shield") {
            InspectorValueGrid(values: [
                ("Confidence", value.confidence.rawValue.capitalized),
                ("Executable", value.executableArchitecture.rawValue),
                ("DirectX", value.detectedDirectX.api?.displayName ?? "Unconfirmed"),
                ("Prefix", value.recommendedPrefixMode.displayName),
                ("Windows", value.recommendedWindowsVersion.displayName),
                ("Graphics", value.recommendedGraphicsStack.backend.displayName)
            ])
            evidenceList("DirectX evidence", value.detectedDirectX.evidence.map { "\($0.source): \($0.detail)" })
            if !value.warnings.isEmpty {
                Divider()
                ForEach(value.warnings) { warning in
                    Label(warning.title + ": " + warning.detail, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var dependencyCard: some View {
        InspectorCard(title: "Static dependencies", symbol: "shippingbox") {
            if dependencies.isEmpty {
                Text("No dependency evidence was found in the executable or related DLLs.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dependencies) { dependency in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: dependency.isInstalled ? "checkmark.circle.fill" : "questionmark.circle")
                            .foregroundStyle(dependency.isInstalled ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dependency.dependency.displayName)
                                .fontWeight(.medium)
                            Text(dependency.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !dependency.evidence.isEmpty {
                                Text(dependency.evidence.map(\.library).joined(separator: ", "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(dependency.confidence.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func diagnosisCard(_ value: LaunchFailureDiagnosis) -> some View {
        InspectorCard(title: "Last launch diagnosis", symbol: "stethoscope") {
            Label(value.summary, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Category: \(value.category.rawValue) · Confidence: \(value.confidence.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            evidenceList("Evidence", value.evidence.map { "\($0.source): \($0.detail)" })
            if !value.suggestedActions.isEmpty {
                Text("Suggested actions")
                    .font(.subheadline.weight(.medium))
                ForEach(value.suggestedActions) { action in
                    if action.kind == .installDependency {
                        Button(action.title, systemImage: action.kind.symbol) {
                            confirmsRepair = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Label(action.title, systemImage: action.kind.symbol)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func evidenceList(_ title: String, _ values: [String]) -> some View {
        Group {
            if !values.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.medium))
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func loadingCard(_ title: String) -> some View {
        InspectorCard(title: "Working", symbol: "hourglass") {
            HStack {
                ProgressView().controlSize(.small)
                Text(title).foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() async {
        async let resolved = store.resolveCompatibility(for: application.id)
        async let analyzed = store.analyzeDependencies(for: application.id)
        resolution = await resolved
        dependencies = await analyzed
        snapshots = await store.environmentSnapshots(for: application.environmentID)
        diagnosis = await store.diagnoseLaunchFailure(for: application.id)
    }

    private var snapshotCard: some View {
        InspectorCard(title: "Environment history", symbol: "clock.arrow.circlepath") {
            if snapshots.isEmpty {
                Text("No snapshots have been published for this environment yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshots) { snapshot in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.reason.rawValue)
                            Text("\(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: snapshot.sizeBytes ?? 0, countStyle: .file)) · trace \(snapshot.traceID.shortValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { snapshotToRestore = snapshot }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button(role: .destructive) { snapshotToDelete = snapshot } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

struct GameSavesView: View {
    @Environment(BorealStore.self) private var store
    let application: WindowsApplication
    @State private var locations: [GameSaveLocation] = []
    @State private var backups: [GameSaveBackup] = []
    @State private var selectedBackup: GameSaveBackup?
    @State private var isWorking = false
    @State private var message: String?
    @State private var manualPath = ""
    @State private var manualPaths: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Detected locations") {
                    if locations.isEmpty {
                        Text("No existing save data was found at the known locations.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(locations) { location in
                            HStack {
                                Image(systemName: "folder")
                                VStack(alignment: .leading) {
                                    Text(location.relativePath).font(.callout.monospaced())
                                    Text("\(location.source.rawValue) · \(location.confidence.rawValue) confidence")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Backups") {
                    if backups.isEmpty {
                        Text("No save backups have been created.").foregroundStyle(.secondary)
                    } else {
                        ForEach(backups) { backup in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    Text("\(backup.trigger.rawValue) · \(ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") { selectedBackup = backup }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                Section("Manual locations") {
                    ForEach(manualPaths, id: \.self) { path in
                        HStack {
                            Text(path).font(.callout.monospaced())
                            Spacer()
                            Button(role: .destructive) {
                                manualPaths.removeAll { $0 == path }
                                Task { await saveManualPaths() }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("relative/path/to/saves", text: $manualPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let value = manualPath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            let components = value.split(separator: "/")
                            guard !value.isEmpty, !components.contains(".."), !manualPaths.contains(value) else { return }
                            manualPaths.append(value)
                            manualPath = ""
                            Task { await saveManualPaths() }
                        }
                    }
                    Text("Paths are relative to the installed game or managed prefix. Boreal never backs up the whole prefix as save data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Saves · \(application.name)")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Create Backup", systemImage: "arrow.down.doc") {
                        Task { await createBackup() }
                    }
                    .disabled(isWorking || locations.isEmpty)
                }
            }
            .overlay {
                if isWorking { ProgressView("Updating save data…") }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task { await refresh() }
        .alert("Save backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog("Restore this save backup?", isPresented: Binding(get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil } })) {
            Button("Restore", role: .destructive) {
                guard let selectedBackup else { return }
                Task { await restore(selectedBackup) }
            }
            Button("Cancel", role: .cancel) { selectedBackup = nil }
        } message: {
            Text("Existing files at the detected save locations will be replaced by the backup.")
        }
    }

    private func refresh() async {
        locations = await store.detectedSaveLocations(for: application.id)
        backups = await store.saveBackups(for: application.id)
        manualPaths = await store.advancedConfiguration(for: application.id).manualSavePaths
    }

    private func saveManualPaths() async {
        var configuration = await store.advancedConfiguration(for: application.id)
        configuration.manualSavePaths = manualPaths
        configuration.updatedAt = .now
        do {
            try await store.updateAdvancedConfiguration(configuration)
            locations = await store.detectedSaveLocations(for: application.id)
        } catch {
            message = error.localizedDescription
        }
    }

    private func createBackup() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await store.createSaveBackup(for: application.id)
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore(_ backup: GameSaveBackup) async {
        isWorking = true
        defer { isWorking = false; selectedBackup = nil }
        do {
            try await store.restoreSaveBackup(backup)
            message = "Save backup restored."
        } catch {
            message = error.localizedDescription
        }
    }
}

struct GameAdvancedConfigurationView: View {
    @Environment(BorealStore.self) private var store
    let application: WindowsApplication
    @State private var configuration: GameAdvancedConfiguration
    @State private var newDLL = ""
    @State private var newDLLMode: DLLOverrideMode = .nativeThenBuiltin
    @State private var newVariableKey = ""
    @State private var newVariableValue = ""
    @State private var message: String?

    init(application: WindowsApplication) {
        self.application = application
        _configuration = State(initialValue: GameAdvancedConfiguration(applicationID: application.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("DLL overrides") {
                    ForEach(configuration.dllOverrides, id: \.self) { override in
                        HStack {
                            Text(override.library).font(.body.monospaced())
                            Spacer()
                            Text(override.mode.rawValue)
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                configuration.dllOverrides.removeAll { $0 == override }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("library.dll", text: $newDLL)
                            .textFieldStyle(.roundedBorder)
                        Picker("Mode", selection: $newDLLMode) {
                            ForEach(DLLOverrideMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Button("Add") {
                            let library = newDLL.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard library.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { return }
                            configuration.dllOverrides.append(DLLOverride(library: library, mode: newDLLMode))
                            newDLL = ""
                        }
                    }
                    Text("If a library is managed by the selected graphics stack, Boreal keeps the managed override and records a conflict warning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Environment variables") {
                    ForEach(configuration.environmentVariables, id: \.self) { variable in
                        HStack {
                            Toggle(variable.key, isOn: Binding(
                                get: { configuration.environmentVariables.first(where: { $0.id == variable.id })?.enabled ?? false },
                                set: { enabled in
                                    guard let index = configuration.environmentVariables.firstIndex(where: { $0.id == variable.id }) else { return }
                                    configuration.environmentVariables[index].enabled = enabled
                                }
                            ))
                            Text(variable.value).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                configuration.environmentVariables.removeAll { $0.id == variable.id }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("KEY", text: $newVariableKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("value", text: $newVariableValue)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let key = newVariableKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !key.isEmpty else { return }
                            configuration.environmentVariables.append(CustomEnvironmentVariable(key: key, value: newVariableValue, enabled: true))
                            newVariableKey = ""
                            newVariableValue = ""
                        }
                    }
                    Text("Boreal-owned keys such as WINEPREFIX, PATH and WINEARCH are rejected at launch time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Controller profile") {
                    Picker("Input mode", selection: $configuration.controllerProfile.inputMode) {
                        ForEach(ControllerInputMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .disabled(true)
                    Text("Automatic is the only input mode currently connected to this launch path.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Stick deadzone") {
                        Slider(value: $configuration.controllerProfile.deadZone, in: 0.05...0.9, step: 0.05)
                    }
                    Toggle("Allow controller navigation in Boreal", isOn: $configuration.controllerProfile.desktopNavigationEnabled)
                    Toggle("Mouse and keyboard emulation", isOn: $configuration.controllerProfile.mouseEmulationEnabled)
                        .disabled(true)
                    Text("Mouse emulation is kept unavailable until it can be applied without stealing input from the game.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Save per-game configuration", systemImage: "checkmark") {
                        Task {
                            do {
                                configuration.updatedAt = .now
                                try await store.updateAdvancedConfiguration(configuration)
                                message = "Configuration saved for the next launch."
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Advanced · \(application.name)")
        }
        .frame(minWidth: 640, minHeight: 520)
        .task { configuration = await store.advancedConfiguration(for: application.id) }
        .alert("Per-game configuration", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

private struct InspectorCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            content
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct InspectorValueGrid: View {
    let values: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                VStack(alignment: .leading, spacing: 3) {
                    Text(value.0).font(.caption).foregroundStyle(.secondary)
                    Text(value.1).font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
