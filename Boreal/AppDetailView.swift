import AppKit
import SwiftUI

struct AppDetailView: View {
    @Environment(BorealStore.self) private var store
    let app: WindowsApplication
    let didRemove: () -> Void
    @State private var showsRemoveConfirmation = false
    @State private var showsRenameDialog = false
    @State private var renameValue = ""
    @State private var showsAdvanced = false
    @State private var showsCompatibilityConfigurator = false
    @AppStorage("developerMode") private var developerMode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 24) {
                    AppIconView(symbol: app.iconSymbol, size: 112)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(app.name).font(.largeTitle).fontWeight(.semibold)
                        Text(app.publisher).foregroundStyle(.secondary)
                        ApplicationStatusLabel(status: app.status)
                        HStack(spacing: 12) {
                            primaryAction
                                .buttonStyle(.borderedProminent).controlSize(.large)
                            Menu {
                                Button("Compatibility Settings…", systemImage: "slider.horizontal.3") { showsCompatibilityConfigurator = true }
                                let gameActions = store.auxiliaryExecutables(for: app)
                                if !gameActions.isEmpty {
                                    Divider()
                                    Section("Game Actions") {
                                        ForEach(gameActions) { action in
                                            Button(action.displayName, systemImage: action.role.symbol) {
                                                store.runAuxiliaryExecutable(action, for: app.id)
                                            }
                                            .disabled(app.status == .running || app.status.isBusy)
                                        }
                                    }
                                }
                                Divider()
                                Button("Show in Finder", systemImage: "folder") { revealExecutable() }
                                if isCustomInstalled {
                                    Button("Rename Game…", systemImage: "pencil") {
                                        renameValue = app.name
                                        showsRenameDialog = true
                                    }
                                }
                                if app.status == .running {
                                    Button("Force Quit", systemImage: "xmark.octagon", role: .destructive) { store.forceQuit(app.id) }
                                }
                                if developerMode, let environment = store.environment(id: app.environmentID) {
                                    Divider()
                                    Button("Open C: Drive", systemImage: "externaldrive") { openCDrive(environment) }
                                    Button("View Logs", systemImage: "doc.text.magnifyingglass") { openLogs(environment) }
                                }
                                Divider()
                                Button("Remove App…", systemImage: "trash", role: .destructive) { showsRemoveConfirmation = true }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                        }.padding(.top, 5)
                    }
                    Spacer()
                }

                if app.status == .needsAttention { attentionCard }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 24) {
                    GridRow {
                        infoGroup("Compatibility") {
                            CompatibilityLabel(rating: app.compatibility)
                            if let profile = app.communityCompatibility {
                                Text("Wine · \(profile.tier.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(app.compatibility == .unknown ? "No unambiguous compatibility result found." : "Configuration verified by Boreal.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        infoGroup("Environment") {
                            Text(app.windowsVersion)
                            Label(store.environment(id: app.environmentID) == nil ? "Unavailable" : "Ready", systemImage: store.environment(id: app.environmentID) == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(store.environment(id: app.environmentID) == nil ? .red : .green)
                        }
                    }
                    GridRow {
                        infoGroup("Graphics") {
                            Text(app.graphics)
                            Text(graphicsSummary).font(.caption).foregroundStyle(.secondary)
                        }
                        infoGroup("Storage") {
                            Text(store.formattedBytes(app.storageBytes))
                            Text("Application and environment data").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                DisclosureGroup("Configuration", isExpanded: $showsAdvanced) {
                    VStack(spacing: 2) {
                        DetailRow(title: "Windows version", value: app.windowsVersion, symbol: "rectangle.on.rectangle")
                        DetailRow(title: "Graphics", value: app.graphics, symbol: "display")
                        DetailRow(title: "Environment", value: store.environment(id: app.environmentID)?.name ?? "Unavailable", symbol: "externaldrive")
                        DetailRow(title: "Executable", value: URL(fileURLWithPath: app.executablePath).lastPathComponent, symbol: "doc.badge.gearshape")
                        ForEach(store.auxiliaryExecutables(for: app)) { action in
                            DetailRow(
                                title: action.role.displayName,
                                value: URL(fileURLWithPath: action.executablePath).lastPathComponent,
                                symbol: action.role.symbol
                            )
                        }
                    }.padding(.top, 10)
                }

                Button("Configure Wine…", systemImage: "slider.horizontal.3") {
                    showsCompatibilityConfigurator = true
                }
                .buttonStyle(.bordered)
                .disabled(app.status == .running || app.status.isBusy)

                activitySection

                if let environment = store.environment(id: app.environmentID) {
                    environmentSection(environment)
                }
            }
            .padding(36)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .confirmationDialog("Remove \(app.name)?", isPresented: $showsRemoveConfirmation) {
            Button("Remove App and Environment", role: .destructive) { store.removeApplication(app.id); didRemove() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This removes the app from Boreal. The original setup file is not deleted.") }
        .alert("Rename Game", isPresented: $showsRenameDialog) {
            TextField("Game name", text: $renameValue)
            Button("Cancel", role: .cancel) { renameValue = "" }
            Button("Rename") {
                store.renameCustomApplication(app.id, to: renameValue)
                renameValue = ""
            }
            .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Boreal will search Steam, Epic Games and GOG for artwork, description and other game details.")
        }
        .sheet(isPresented: $showsCompatibilityConfigurator) {
            WineCompatibilityConfigurator(application: store.application(id: app.id) ?? app)
        }
    }

    private var isCustomInstalled: Bool {
        !app.isSteamRuntimeHost && (app.storeProvider == nil || app.usesStoreMetadataOnly)
    }

    @ViewBuilder private var primaryAction: some View {
        switch app.status {
        case .running:
            Button("Stop", systemImage: "stop.fill") { store.toggleRunning(app.id) }
                .keyboardShortcut(.space, modifiers: [.command])
        case .preparing, .starting, .installing:
            Button(app.status == .starting ? "Starting…" : "Preparing…", systemImage: "hourglass") { }
                .disabled(true)
        case .needsAttention:
            Button("Try Again", systemImage: "arrow.clockwise") { store.retry(app.id) }
                .keyboardShortcut(.defaultAction)
        case .unavailable:
            Button("Unavailable", systemImage: "xmark.circle") { }.disabled(true)
        case .ready:
            Button("Open", systemImage: "play.fill") { store.toggleRunning(app.id) }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(app.name) couldn’t open", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Boreal prepared the Windows environment, but the application exited unexpectedly.")
            HStack {
                Button("Try Again", systemImage: "arrow.clockwise") { store.retry(app.id) }
                    .buttonStyle(.borderedProminent)
                if canRecreateWithGPTK {
                    Button("Recreate Environment with GPTK", systemImage: "arrow.triangle.2.circlepath") {
                        store.recreateEnvironment(app.id, with: .gamePortingToolkit)
                    }
                }
                if let detail = app.lastErrorDetail {
                    DisclosureGroup("Details") {
                        Text(detail).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(.top, 6)
                    }
                }
            }
        }
        .padding(16)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.25)))
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity").font(.headline)
            VStack(spacing: 2) {
                DetailRow(title: "Last opened", value: app.lastOpened?.formatted(date: .abbreviated, time: .shortened) ?? "Never", symbol: "clock")
                DetailRow(title: "Last result", value: app.lastResult ?? "No activity yet", symbol: "checkmark.circle")
                DetailRow(title: "Runtime", value: store.environment(id: app.environmentID)?.runtime ?? "Unavailable", symbol: "gearshape.2")
                if let code = app.lastExitCode, developerMode {
                    DetailRow(title: "Exit code", value: String(code), symbol: "terminal")
                }
            }
        }
    }

    private func environmentSection(_ environment: WindowsEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Environment").font(.headline)
            VStack(spacing: 2) {
                DetailRow(title: "Windows", value: environment.windowsVersion, symbol: "rectangle.on.rectangle")
                DetailRow(title: "Status", value: "Ready", symbol: "checkmark.circle")
                DetailRow(title: "Created", value: environment.createdAt.formatted(date: .abbreviated, time: .omitted), symbol: "calendar")
                DetailRow(title: "Storage", value: store.formattedBytes(environment.storageBytes), symbol: "internaldrive")
            }
            HStack {
                Button("Open C: Drive", systemImage: "folder") { openCDrive(environment) }
                if canRecreateWithGPTK {
                    Button("Recreate Environment with GPTK", systemImage: "arrow.triangle.2.circlepath") {
                        store.recreateEnvironment(app.id, with: .gamePortingToolkit)
                    }
                }
                if developerMode {
                    Button("Reveal Environment in Finder", systemImage: "finder") {
                        if let root = environment.rootPath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root)]) }
                    }
                    Button("View Logs", systemImage: "doc.text.magnifyingglass") { openLogs(environment) }
                }
            }
        }
    }

    private var canRecreateWithGPTK: Bool {
        app.storeProvider == .gog
            && app.storeExternalID == "2022341186"
            && store.environment(id: app.environmentID)?.graphics != RuntimeEngine.gamePortingToolkit.graphicsName
            && app.status != .running
            && !app.status.isBusy
    }

    private var graphicsSummary: String {
        let profile = store.compatibilityProfile(for: app)
        let api = profile.graphicsAPI ?? GameGraphicsProfiles.profile(for: app)?.defaultAPI ?? .automatic
        return "\(api.displayName) · \(profile.graphicsBackend.displayName) translation"
    }

    private func infoGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealExecutable() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.executablePath)])
    }

    private func openCDrive(_ environment: WindowsEnvironment) {
        guard let prefix = environment.prefixPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: prefix).appending(path: "drive_c"))
    }

    private func openLogs(_ environment: WindowsEnvironment) {
        guard let logs = environment.logsPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: logs))
    }
}
