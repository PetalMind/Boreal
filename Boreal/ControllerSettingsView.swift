import SwiftUI

struct ControllerSettingsView: View {
    @State private var manager = ControllerManager.shared

    var body: some View {
        Form {
            Section("Detected controllers") {
                if manager.controllers.isEmpty {
                    ContentUnavailableView(
                        "No controller detected",
                        systemImage: "gamecontroller",
                        description: Text("Connect a wired controller or pair one in System Settings. Boreal updates this list automatically.")
                    )
                } else {
                    ForEach(manager.controllers) { controller in
                        HStack(spacing: 12) {
                            Image(systemName: controller.supportsExtendedProfile ? "gamecontroller.fill" : "gamecontroller")
                                .font(.title2).foregroundStyle(.cyan)
                            VStack(alignment: .leading) {
                                Text(controller.name).fontWeight(.medium)
                                Text(controller.supportsExtendedProfile ? controller.category : "\(controller.category) · basic profile")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                if let input = manager.lastInput {
                    LabeledContent("Last input", value: input.displayName)
                }
            }

            Section("Controller mapping") {
                Toggle("Enable keyboard mapping for Windows games", isOn: $manager.isMappingEnabled)
                Text("Boreal translates controller input to keyboard input while a Windows game is running. Native controller support in the game remains available.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ControllerInput.allCases) { input in
                    Picker(input.displayName, selection: binding(for: input)) {
                        ForEach(ControllerKey.allCases) { key in Text(key.displayName).tag(key) }
                    }
                }
                LabeledContent("Stick dead zone") {
                    HStack {
                        Slider(value: deadZoneBinding, in: 0.15...0.9, step: 0.05).frame(width: 180)
                        Text(manager.mapping.stickDeadZone.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit().frame(width: 38)
                    }
                }
                Button("Restore default mapping", systemImage: "arrow.counterclockwise") { manager.resetMapping() }
            }

            Section("Input permission") {
                if manager.accessibilityGranted {
                    Label("Boreal can send mapped input to games", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                } else {
                    Label("Accessibility permission is required to send mapped keys", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Button("Open permission prompt") { manager.requestAccessibilityAccess() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 720)
        .navigationTitle("Controllers")
        .onAppear {
            manager.start()
            manager.refreshPermissionState()
        }
    }

    private func binding(for input: ControllerInput) -> Binding<ControllerKey> {
        Binding(
            get: { manager.mapping[input] },
            set: { value in
                var mapping = manager.mapping
                mapping[input] = value
                manager.mapping = mapping
            }
        )
    }

    private var deadZoneBinding: Binding<Double> {
        Binding(
            get: { Double(manager.mapping.stickDeadZone) },
            set: { value in
                var mapping = manager.mapping
                mapping.stickDeadZone = Float(value)
                manager.mapping = mapping
            }
        )
    }
}
