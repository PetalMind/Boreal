import AppKit
import SwiftUI

struct WineCompatibilityConfigurator: View {
    private struct DisplayChoice: Identifiable {
        let id: UInt32
        let label: String
    }

    @Environment(BorealStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let application: WindowsApplication
    @State private var profile: WineCompatibilityProfile
    @State private var detectedGraphicsAPI: GraphicsAPI?
    @State private var controllerManager = ControllerManager.shared
    @State private var showsControllerMapping = false

    init(application: WindowsApplication) {
        self.application = application
        _profile = State(initialValue: application.resolvedCompatibilityProfile)
        _detectedGraphicsAPI = State(initialValue: nil)
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
                Section {
                    HStack {
                        presetButton("Recommended", symbol: "wand.and.stars", profile: .default)
                        presetButton("Older game", symbol: "clock.arrow.circlepath", profile: olderGameProfile)
                        presetButton("Performance", symbol: "gauge.with.dots.needle.67percent", profile: performanceProfile)
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("Quick setup")
                } footer: {
                    Text("Choose a starting point, then adjust the settings below. Presets replace all settings in this dialog.")
                }
                if usesSharedSteamEnvironment {
                    Label("Steam shares its Windows environment across games. Architecture, graphics renderer and older-game fixes are managed there.", systemImage: "person.2.fill")
                        .font(.callout).foregroundStyle(.secondary)
                }

                Section("Graphics") {
                    Picker("DirectX version", selection: graphicsAPIBinding) {
                        ForEach(GraphicsAPI.allCases) { api in
                            Text(graphicsAPILabel(for: api)).tag(api)
                        }
                    }
                    Text(graphicsAPIExplanation)
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("Graphics renderer", selection: $profile.graphicsBackend) {
                        ForEach(WineGraphicsBackend.allCases) { backend in
                            Text(backendLabel(backend)).tag(backend)
                        }
                    }
                    .disabled(usesSharedSteamEnvironment)
                    Text(graphicsBackendExplanation)
                        .font(.caption).foregroundStyle(.secondary)
                    if let issue = graphicsBackendIssue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section("Display") {
                    Toggle("High-resolution rendering (Retina)", isOn: $profile.retinaModeEnabled)
                    Toggle("Fullscreen upscaling (FSR)", isOn: $profile.fullscreenFSREnabled)
                    Text("Retina gives a sharper image. FSR can improve performance when playing fullscreen at a lower resolution; runtime support is required.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Keep Boreal overlay visible", isOn: $profile.overlayCompatibleFullscreen)
                    Text("Uses a borderless fullscreen window so the game does not cover the overlay.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Game display", selection: $profile.overlayDisplayID) {
                        Text("Automatic (main display)").tag(Optional<UInt32>.none)
                        ForEach(availableDisplays) { display in
                            Text(display.label).tag(Optional(display.id))
                        }
                    }
                    .disabled(!profile.overlayCompatibleFullscreen)
                    Text("Choose which screen the borderless game window uses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Controller") {
                    if let controller = controllerManager.controllers.first {
                        HStack(spacing: 12) {
                            Image(systemName: controller.supportsExtendedProfile ? "gamecontroller.fill" : "gamecontroller")
                                .font(.title2)
                                .foregroundStyle(controller.supportsExtendedProfile ? .green : .red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(controller.name).fontWeight(.medium)
                                Text("Connected").font(.caption).foregroundStyle(.green)
                            }
                            Spacer()
                        }
                        LabeledContent("Controller mode", value: profile.forceXInput ? "Xbox 360 Controller" : "Native Wine controller")
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "gamecontroller")
                                .font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("No controller detected").fontWeight(.medium)
                            }
                        }
                    }

                    Toggle("Disable keyboard mapping", isOn: $profile.disableSteamInputEquivalent)
                    Text("Stops Boreal from turning controller buttons into keyboard presses. Steam Input is unchanged.")
                        .font(.caption).foregroundStyle(.secondary)

                    Toggle("Xbox controller compatibility", isOn: $profile.forceXInput)
                    Text("Presents the controller as an Xbox 360 controller. Restart the entire Wine session after changing this.")
                        .font(.caption).foregroundStyle(.secondary)

                    Button("Controller mapping", systemImage: "gamecontroller") {
                        showsControllerMapping = true
                    }
                }

                Section {
                    DisclosureGroup("Windows environment") {
                        Picker("Windows version", selection: $profile.windowsVersion) {
                            ForEach(WineWindowsVersion.allCases) { version in
                                Text(version.displayName).tag(version)
                            }
                        }
                        Picker("Architecture", selection: $profile.architecture) {
                            ForEach(WinePrefixArchitecture.allCases) { architecture in
                                Text(architecture.displayName).tag(architecture)
                            }
                        }
                        .disabled(usesSharedSteamEnvironment)
                        Text("Changing architecture rebuilds the Windows environment. Your game files stay in place.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    DisclosureGroup("Older games") {
                        Picker("Compatibility fix", selection: $profile.legacyWrapper) {
                            ForEach(LegacyGraphicsWrapper.allCases) { wrapper in
                                Text(wrapper.displayName).tag(wrapper)
                            }
                        }
                        .disabled(usesSharedSteamEnvironment)
                        if profile.legacyWrapper == .dgVoodoo2 {
                            Picker("Older graphics API", selection: $profile.legacyGraphicsAPI) {
                                ForEach(LegacyGraphicsAPI.allCases) { api in
                                    Text(api.displayName).tag(api)
                                }
                            }
                            Text("Uses dgVoodoo2 for the selected graphics API. Requires a runtime that includes dgVoodoo2.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("For older games that use DirectDraw or early Direct3D. Leave disabled unless needed.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    DisclosureGroup("Performance") {
                        Toggle("ESync", isOn: $profile.esyncEnabled)
                        Toggle("MSync", isOn: $profile.msyncEnabled)
                        Text("These options can reduce CPU overhead. Support depends on the Wine runtime.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    DisclosureGroup("Launch and diagnostics") {
                        TextField("Launch arguments", text: $profile.launchArguments, prompt: Text("e.g. -windowed -novsync"))
                            .textFieldStyle(.roundedBorder)
                        Toggle("Verbose Wine logging", isOn: $profile.debugLoggingEnabled)
                        Text("Verbose logging can create large log files. Enable it only while diagnosing a problem.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Change these only to solve a specific problem with this game.")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Restore defaults") { profile = .default }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save changes") {
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
            controllerManager.start()
        }
        .sheet(isPresented: $showsControllerMapping) {
            NavigationStack { ControllerSettingsView() }
        }
        .task(id: application.executablePath) {
            guard graphicsProfile == nil,
                  FileManager.default.fileExists(atPath: application.executablePath) else { return }
            let executable = URL(fileURLWithPath: application.executablePath)
            let detected = await Task.detached(priority: .utility) {
                GraphicsAPIDetector.detect(executable: executable)
            }.value
            guard !Task.isCancelled else { return }
            detectedGraphicsAPI = detected
            if profile.graphicsAPI == nil { profile.graphicsAPI = detected }
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
        application.usesSharedSteamEnvironment
    }

    private var availableDisplays: [DisplayChoice] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = UInt32(number.uint32Value)
            let pixelSize = screen.convertRectToBacking(screen.frame).size
            return DisplayChoice(id: id, label: "Display \(index + 1) — \(Int(pixelSize.width))×\(Int(pixelSize.height))")
        }
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

    private var graphicsBackendExplanation: String {
        switch profile.graphicsBackend {
        case .automatic: "Chooses an available renderer for this game."
        case .d3dMetal: "For DirectX 11 and 12. Requires Game Porting Toolkit."
        case .dxmt: "Runs DirectX 11 using Metal. Requires DXMT support."
        case .dxvk: "Runs DirectX 10 and 11 using Vulkan. DirectX 9 uses WineD3D."
        case .wineD3D: "A fallback to try if other renderers cause graphics problems."
        }
    }

    private var graphicsAPIExplanation: String {
        let selectedAPI = graphicsAPIBinding.wrappedValue
        guard selectedAPI != .automatic else {
            return "Uses the detected DirectX version. Choose a specific version only if the game supports it."
        }
        if graphicsProfile?.launchOption(for: selectedAPI) != nil {
            return "Boreal will request \(selectedAPI.displayName) when this game starts."
        }
        return "This preference alone cannot switch the game to \(selectedAPI.displayName). Set it in the game or add its documented launch argument under Advanced → Launch and diagnostics."
    }
}
