import SwiftUI

struct WineCompatibilityConfigurator: View {
    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let application: WindowsApplication
    @State private var profile: WineCompatibilityProfile

    init(application: WindowsApplication) {
        self.application = application
        _profile = State(initialValue: application.resolvedCompatibilityProfile)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .background(.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Compatibility settings").font(.title2.weight(.semibold))
                    Text(application.name).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)

            Divider()

            Form {
                Section("Quick setup") {
                    HStack {
                        presetButton("Recommended", symbol: "wand.and.stars", profile: .default)
                        presetButton("Older game", symbol: "clock.arrow.circlepath", profile: olderGameProfile)
                        presetButton("Performance", symbol: "gauge.with.dots.needle.67percent", profile: performanceProfile)
                    }
                    .buttonStyle(.bordered)
                }

                Section("Windows environment") {
                    Picker("Windows version", selection: $profile.windowsVersion) {
                        ForEach(WineWindowsVersion.allCases) { version in
                            Text(version.displayName).tag(version)
                        }
                    }
                    Picker("Prefix architecture", selection: $profile.architecture) {
                        ForEach(WinePrefixArchitecture.allCases) { architecture in
                            Text(architecture.displayName).tag(architecture)
                        }
                    }
                    .disabled(usesSharedSteamEnvironment)
                    Text("Architecture is fixed when a Wine prefix is created. Changing it rebuilds the isolated environment; game files stay in place.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Graphics and DirectX") {
                    Picker("Graphics API", selection: graphicsAPIBinding) {
                        ForEach(GraphicsAPI.allCases) { api in
                            Text(graphicsAPILabel(for: api)).tag(api)
                        }
                    }
                    Text(graphicsAPIExplanation)
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("Translation backend", selection: $profile.graphicsBackend) {
                        ForEach(WineGraphicsBackend.allCases) { backend in
                            Text(backendLabel(backend)).tag(backend)
                        }
                    }
                    .disabled(usesSharedSteamEnvironment)
                    Text(profile.graphicsBackend.detail)
                        .font(.caption).foregroundStyle(.secondary)
                    if let issue = graphicsBackendIssue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    } else if profile.graphicsBackend == .d3dMetal {
                        Label("Requires a Game Porting Toolkit runtime.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if usesSharedSteamEnvironment {
                        Label("Steam games use one shared client environment. Architecture and renderer are managed for that environment; the remaining options are still saved for this game.", systemImage: "person.2.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Legacy graphics compatibility") {
                    Picker("Legacy wrapper", selection: $profile.legacyWrapper) {
                        ForEach(LegacyGraphicsWrapper.allCases) { wrapper in
                            Text(wrapper.displayName).tag(wrapper)
                        }
                    }
                    .disabled(usesSharedSteamEnvironment)
                    if profile.legacyWrapper == .dgVoodoo2 {
                        Picker("Legacy API", selection: $profile.legacyGraphicsAPI) {
                            ForEach(LegacyGraphicsAPI.allCases) { api in
                                Text(api.displayName).tag(api)
                            }
                        }
                        Text("Boreal installs only the selected wrapper DLL beside the game executable. The runtime must supply a managed dgVoodoo2 component.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Enable this only for games that use DirectDraw or an early Direct3D renderer.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if usesSharedSteamEnvironment {
                        Label("Per-game wrappers are not available for games launched through the shared Windows Steam client in this first version.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Reset graphics configuration", systemImage: "arrow.counterclockwise") {
                        profile.graphicsBackend = .automatic
                        profile.legacyWrapper = .none
                        profile.legacyGraphicsAPI = .directDraw
                    }
                }

                Section("Performance") {
                    Toggle("ESync synchronization", isOn: $profile.esyncEnabled)
                    Toggle("MSync synchronization", isOn: $profile.msyncEnabled)
                    Toggle("Retina rendering", isOn: $profile.retinaModeEnabled)
                    Toggle("Fullscreen FSR scaling", isOn: $profile.fullscreenFSREnabled)
                }

                Section("Advanced") {
                    TextField("Launch arguments", text: $profile.launchArguments, prompt: Text("e.g. -windowed -novsync"))
                        .textFieldStyle(.roundedBorder)
                    Toggle("Verbose Wine logging", isOn: $profile.debugLoggingEnabled)
                    Text("Verbose logging can create large log files. Enable it only while diagnosing a problem.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Reset") { profile = .default }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save configuration") {
                    store.updateCompatibilityProfile(for: application.id, profile: profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(application.status == .running || application.status.isBusy || graphicsBackendIssue != nil)
            }
            .padding(18)
        }
        .frame(width: 620, height: 820)
        .onAppear {
            profile = store.compatibilityProfile(for: application)
        }
    }

    private func presetButton(_ title: String, symbol: String, profile value: WineCompatibilityProfile) -> some View {
        Button { profile = value } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
    }

    private var olderGameProfile: WineCompatibilityProfile {
        WineCompatibilityProfile(
            windowsVersion: .windows7,
            architecture: .win32,
            graphicsBackend: .wineD3D,
            esyncEnabled: true,
            msyncEnabled: false,
            retinaModeEnabled: false
        )
    }

    private var performanceProfile: WineCompatibilityProfile {
        WineCompatibilityProfile(
            windowsVersion: .windows10,
            architecture: .win64,
            graphicsBackend: .d3dMetal,
            esyncEnabled: true,
            msyncEnabled: true,
            retinaModeEnabled: true,
            fullscreenFSREnabled: true
        )
    }

    private var usesSharedSteamEnvironment: Bool {
        application.storeProvider == .steam || application.isSteamRuntimeHost
    }

    private var graphicsProfile: GameGraphicsProfile? {
        GameGraphicsProfiles.profile(for: application)
    }

    private var graphicsBackendIssue: String? {
        store.graphicsBackendIssue(profile.graphicsBackend, for: application)
    }

    private func backendLabel(_ backend: WineGraphicsBackend) -> String {
        store.graphicsBackendIssue(backend, for: application) == nil
            ? backend.displayName
            : backend.displayName + " · unavailable"
    }

    private var graphicsAPIBinding: Binding<GraphicsAPI> {
        Binding(
            get: { profile.graphicsAPI ?? graphicsProfile?.defaultAPI ?? .automatic },
            set: { profile.graphicsAPI = $0 }
        )
    }

    private func graphicsAPILabel(for api: GraphicsAPI) -> String {
        if let graphicsProfile, api == graphicsProfile.defaultAPI { return api.displayName + " · Recommended" }
        if graphicsProfile == nil, api == detectedGraphicsAPI { return api.displayName + " · Detected" }
        if let graphicsProfile, api != .automatic, !graphicsProfile.availableAPIs.contains(api) {
            return api.displayName + " · Manual"
        }
        return api.displayName
    }

    private var detectedGraphicsAPI: GraphicsAPI? {
        guard FileManager.default.fileExists(atPath: application.executablePath) else { return nil }
        return GraphicsAPIDetector.detect(executable: URL(fileURLWithPath: application.executablePath))
    }

    private var graphicsAPIExplanation: String {
        let selectedAPI = graphicsAPIBinding.wrappedValue
        guard selectedAPI != .automatic else {
            return "Boreal detects the DirectX imports and selects the best available renderer for this game. You can override both choices here."
        }
        if graphicsProfile?.launchOption(for: selectedAPI) != nil {
            return "Boreal has a verified launch rule for this game and will request \(selectedAPI.displayName) when it starts."
        }
        return "\(selectedAPI.displayName) is saved for this game. There is no universal Wine switch that can force every game to use it; add the game's documented launch argument below when Boreal has no verified rule yet."
    }
}
