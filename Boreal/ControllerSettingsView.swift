import SwiftUI

/// Dedicated controller workspace backed by the real GameController mapping service.
struct ControllerSettingsView: View {
    @State private var manager = ControllerManager.shared
    @State private var category: ControllerSettingsCategory = .general

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                categoryList
                Divider()
                ScrollView {
                    HStack(alignment: .top, spacing: 32) {
                        categoryContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !manager.controllers.isEmpty {
                            ControllerPreview(manager: manager)
                                .frame(width: 420)
                        }
                    }
                    .frame(maxWidth: 1440, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(28)
                }
            }
            Divider()
            footer
        }
        .background(BorealGlassBackdrop())
        .navigationTitle("Controller Settings")
        .onAppear { manager.start(); manager.refreshPermissionState() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gamecontroller.fill").font(.title2).foregroundStyle(.cyan)
                .frame(width: 42, height: 42).background(.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("Controller Settings").font(.title2.weight(.semibold))
                Text(manager.controllers.first?.name ?? "No controller detected").foregroundStyle(.secondary)
            }
            Spacer()
            Label(manager.controllers.isEmpty ? "Not connected" : "Connected", systemImage: manager.controllers.isEmpty ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(manager.controllers.isEmpty ? Color.secondary : Color.green)
                .padding(.horizontal, 12).padding(.vertical, 7).background(.thinMaterial, in: Capsule())
        }.padding(.horizontal, 28).padding(.vertical, 18)
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(ControllerSettingsCategory.allCases) { item in
                Button { category = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).frame(width: 19)
                        Text(item.rawValue)
                        Spacer()
                        if item.isUnavailable { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
                    }
                    .contentShape(Rectangle()).padding(.horizontal, 12).padding(.vertical, 9)
                    .background(category == item ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(category == item ? .primary : .secondary)
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 184, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder private var categoryContent: some View {
        switch category {
        case .general: generalContent
        case .layout: mappingContent
        case .sticks: sticksContent
        case .compatibility: compatibilityContent
        case .triggers: unsupportedContent("Trigger tuning")
        case .gyro: unsupportedContent("Gyroscope")
        case .haptics: unsupportedContent("Haptics")
        case .shortcuts: unsupportedContent("Chord shortcuts")
        case .profiles: unsupportedContent("Controller profiles")
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsSection("General", subtitle: "Configure how Boreal uses the connected controller.") {
                if let controller = manager.controllers.first {
                    DetailRow(title: "Controller", value: controller.name, symbol: "gamecontroller.fill")
                    DetailRow(title: "Connection", value: "Connected", symbol: "dot.radiowaves.left.and.right")
                    DetailRow(title: "Profile", value: controller.supportsExtendedProfile ? "Extended gamepad" : "Basic profile", symbol: "slider.horizontal.3")
                } else {
                    HStack(spacing: 18) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 58, height: 58)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("No controller detected").font(.headline)
                            Text("Connect a controller in System Settings. Boreal will update this screen automatically.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
                Divider()
                Button("Test Controller", systemImage: "waveform.path.ecg") { category = .layout }.disabled(manager.controllers.isEmpty)
            }
            if let input = manager.lastInput {
                settingsSection("Live input", subtitle: "Latest input reported by GameController.") {
                    Label(input.displayName, systemImage: "circle.fill").foregroundStyle(.cyan)
                }
            }
            permissionSection
        }
    }

    private var mappingContent: some View {
        settingsSection("Layout", subtitle: "Map controller inputs to keyboard keys for Windows games.") {
            Toggle("Enable keyboard mapping for Windows games", isOn: mappingEnabledBinding)
            Text("Native controller support remains available. Mapping is applied only to active game sessions.").font(.caption).foregroundStyle(.secondary)
            ForEach(ControllerInput.allCases) { input in
                Picker(input.displayName, selection: binding(for: input)) {
                    ForEach(ControllerKey.allCases) { key in Text(key.displayName).tag(key) }
                }
            }
            Button("Restore default mapping", systemImage: "arrow.counterclockwise") { manager.resetMapping() }
        }
    }

    private var sticksContent: some View {
        settingsSection("Sticks", subtitle: "Adjust the shared deadzone used by controller-to-keyboard mapping.") {
            LabeledContent("Stick deadzone") {
                HStack {
                    Slider(value: deadZoneBinding, in: 0.15...0.9, step: 0.05)
                    Text(manager.mapping.stickDeadZone.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().frame(width: 42, alignment: .trailing)
                }
            }
            Text("Advanced sensitivity, response curves, anti-deadzone and axis inversion are not connected to the current input backend yet.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var compatibilityContent: some View {
        settingsSection("Compatibility", subtitle: "Current Wine integration status.") {
            DetailRow(title: "Input mode", value: "Automatic", symbol: "switch.2")
            DetailRow(title: "Wine exposure", value: "SDL / Wine controller", symbol: "wineglass")
            Text("Per-game XInput and duplicate-input controls are available from each game's Compatibility Settings.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var permissionSection: some View {
        settingsSection("Input permission", subtitle: "Accessibility permission is needed for keyboard mapping.") {
            if manager.accessibilityGranted {
                Label("Boreal can send mapped input to games", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            } else {
                Label("Accessibility permission is required", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button("Open permission prompt") { manager.requestAccessibilityAccess() }
            }
        }
    }

    private func unsupportedContent(_ title: String) -> some View {
        settingsSection(title, subtitle: "Reserved for a future controller backend capability.") {
            Label("Not available yet", systemImage: "lock.fill").foregroundStyle(.secondary)
            Text("Boreal does not expose this control until it can be applied reliably to the active controller and game session.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func settingsSection<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.055), lineWidth: 1))
        }.padding(.bottom, 22)
    }

    private var footer: some View {
        HStack {
            Text("B Back").foregroundStyle(.secondary)
            Spacer()
            Button("Reset", systemImage: "arrow.counterclockwise") { manager.resetMapping() }
            Button("Apply", systemImage: "checkmark") { manager.applyMapping() }.buttonStyle(.borderedProminent)
        }.padding(.horizontal, 28).padding(.vertical, 13)
    }

    private func binding(for input: ControllerInput) -> Binding<ControllerKey> {
        Binding(get: { manager.mapping[input] }, set: { manager.mapping[input] = $0 })
    }

    private var deadZoneBinding: Binding<Double> {
        Binding(get: { Double(manager.mapping.stickDeadZone) }, set: { manager.mapping.stickDeadZone = Float($0) })
    }

    private var mappingEnabledBinding: Binding<Bool> {
        Binding(get: { manager.isMappingEnabled }, set: { manager.isMappingEnabled = $0 })
    }
}

private enum ControllerSettingsCategory: String, CaseIterable, Identifiable {
    case general = "General", layout = "Layout", sticks = "Sticks", triggers = "Triggers", gyro = "Gyro", haptics = "Haptics", compatibility = "Compatibility", shortcuts = "Shortcuts", profiles = "Profiles"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "info.circle"; case .layout: "square.grid.3x3"; case .sticks: "circle.dotted"; case .triggers: "rectangle.compress.vertical"; case .gyro: "gyroscope"; case .haptics: "waveform"; case .compatibility: "wrench.and.screwdriver"; case .shortcuts: "command"; case .profiles: "person.crop.rectangle.stack"
        }
    }
    var isUnavailable: Bool { [.triggers, .gyro, .haptics, .shortcuts, .profiles].contains(self) }
}

private struct ControllerPreview: View {
    let manager: ControllerManager
    private var family: ControllerFamily { manager.controllers.first?.family ?? .generic }
    private var controller: DetectedController? { manager.controllers.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live controller").font(.headline)
                    Text(controller.map { "\($0.name) · Connected" } ?? "No controller connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "rectangle.on.rectangle").foregroundStyle(.cyan)
            }

            Controller2DView(family: family, state: manager.liveState)
                .frame(height: 300)
                .padding(.horizontal, 8)

            if let controller {
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    informationRow("Battery", value: controller.batteryLevel.map {
                        $0.formatted(.percent.precision(.fractionLength(0)))
                    } ?? "Unavailable")
                    informationRow("Connection", value: controller.connectionName)
                    informationRow("Player", value: controller.playerNumber.map(String.init) ?? "Unavailable")
                    informationRow("Profile", value: manager.activeProfileName ?? "No active game")
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                telemetryRow("Left stick", x: manager.liveState.leftStickX, y: manager.liveState.leftStickY)
                telemetryRow("Right stick", x: manager.liveState.rightStickX, y: manager.liveState.rightStickY)
                triggerRow("LT", value: manager.liveState.leftTrigger)
                triggerRow("RT", value: manager.liveState.rightTrigger)
            }
            if let input = manager.lastInput {
                Label(input.displayName, systemImage: "waveform.path.ecg").font(.caption).foregroundStyle(.cyan)
            } else {
                Text("Move a stick or press a button").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.cyan.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    private func telemetryRow(_ title: String, x: Float, y: Float) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text("X \(x.formatted(.number.precision(.fractionLength(2))))")
            Text("Y \(y.formatted(.number.precision(.fractionLength(2))))")
        }.font(.caption.monospacedDigit())
    }

    private func informationRow(_ title: String, value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            Text(value).fontWeight(.medium).gridCellColumns(2)
        }
        .font(.caption)
    }

    private func triggerRow(_ title: String, value: Float) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            ProgressView(value: Double(value)).frame(width: 80)
            Text(value.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
        }.font(.caption)
    }
}
