import ApplicationServices
import Foundation
import GameController
import Observation

@MainActor
@Observable
final class ControllerManager {
    static let shared = ControllerManager()

    private(set) var controllers: [DetectedController] = []
    private(set) var lastInput: ControllerInput?
    private(set) var liveState = ControllerLiveState.idle
    private(set) var accessibilityGranted = AXIsProcessTrusted()
    var isMappingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMappingEnabled, forKey: "controllerMappingEnabled")
            if !isMappingEnabled { releaseAllInputs() }
        }
    }
    var mapping: ControllerMapping {
        didSet { saveMapping() }
    }

    private var observers: [NSObjectProtocol] = []
    private var activeApplications: [UUID: Bool] = [:]
    private var pressedInputs: [ObjectIdentifier: Set<ControllerInput>] = [:]
    private var isStarted = false

    var detectionState: ControllerDetectionState {
        if controllers.contains(where: \.supportsExtendedProfile) { return .ready }
        return controllers.isEmpty ? .unavailable : .unsupported
    }

    private init() {
        isMappingEnabled = UserDefaults.standard.object(forKey: "controllerMappingEnabled") as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: "controllerMapping"),
           let saved = try? JSONDecoder().decode(ControllerMapping.self, from: data) {
            mapping = saved
        } else {
            mapping = .standard
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor in
                    ControllerManager.shared.configure(controller)
                    ControllerManager.shared.refreshControllers()
                    NotificationCenter.default.post(name: .borealControllerConnected, object: nil)
                }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor in
                    ControllerManager.shared.releaseInputs(for: controller)
                    ControllerManager.shared.refreshControllers()
                }
            }
        ]
        GCController.shouldMonitorBackgroundEvents = true
        GCController.controllers().forEach(configure)
        refreshControllers()
        if !controllers.isEmpty {
            NotificationCenter.default.post(name: .borealControllerConnected, object: nil)
        }
        GCController.startWirelessControllerDiscovery {
            Task { @MainActor in ControllerManager.shared.refreshControllers() }
        }
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func refreshPermissionState() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func resetMapping() { mapping = .standard }

    func applyMapping() { saveMapping() }

    func shutdown() {
        activeApplications.removeAll()
        releaseAllInputs()
        GCController.stopWirelessControllerDiscovery()
    }

    func activate(for applicationID: UUID, keyboardMappingEnabled: Bool = true) {
        activeApplications[applicationID] = keyboardMappingEnabled
    }

    func deactivate(for applicationID: UUID) {
        activeApplications[applicationID] = nil
        if !activeApplications.values.contains(true) { releaseAllInputs() }
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.valueChangedHandler = { [weak self, weak controller] gamepad, _ in
            guard let self, let controller else { return }
            Task { @MainActor in self.process(gamepad, controller: controller) }
        }
        process(gamepad, controller: controller)
    }

    private func process(_ gamepad: GCExtendedGamepad, controller: GCController) {
        let deadZone = mapping.stickDeadZone
        let states: [(Bool, ControllerInput)] = [
            (gamepad.buttonA.isPressed, .buttonA), (gamepad.buttonB.isPressed, .buttonB),
            (gamepad.buttonX.isPressed, .buttonX), (gamepad.buttonY.isPressed, .buttonY),
            (gamepad.leftShoulder.isPressed, .leftShoulder), (gamepad.rightShoulder.isPressed, .rightShoulder),
            (gamepad.leftTrigger.value > 0.5, .leftTrigger), (gamepad.rightTrigger.value > 0.5, .rightTrigger),
            (gamepad.buttonMenu.isPressed, .menu), (gamepad.buttonOptions?.isPressed == true, .options),
            (gamepad.leftThumbstickButton?.isPressed == true, .leftThumbstickButton),
            (gamepad.rightThumbstickButton?.isPressed == true, .rightThumbstickButton),
            (gamepad.dpad.up.isPressed, .dpadUp), (gamepad.dpad.down.isPressed, .dpadDown),
            (gamepad.dpad.left.isPressed, .dpadLeft), (gamepad.dpad.right.isPressed, .dpadRight),
            (gamepad.leftThumbstick.yAxis.value > deadZone, .leftStickUp),
            (gamepad.leftThumbstick.yAxis.value < -deadZone, .leftStickDown),
            (gamepad.leftThumbstick.xAxis.value < -deadZone, .leftStickLeft),
            (gamepad.leftThumbstick.xAxis.value > deadZone, .leftStickRight),
            (gamepad.rightThumbstick.yAxis.value > deadZone, .rightStickUp),
            (gamepad.rightThumbstick.yAxis.value < -deadZone, .rightStickDown),
            (gamepad.rightThumbstick.xAxis.value < -deadZone, .rightStickLeft),
            (gamepad.rightThumbstick.xAxis.value > deadZone, .rightStickRight)
        ]
        let current = Set(states.compactMap { isPressed, input in isPressed ? input : nil })
        liveState = ControllerLiveState(
            pressedInputs: current,
            leftStickX: gamepad.leftThumbstick.xAxis.value,
            leftStickY: gamepad.leftThumbstick.yAxis.value,
            rightStickX: gamepad.rightThumbstick.xAxis.value,
            rightStickY: gamepad.rightThumbstick.yAxis.value,
            leftTrigger: gamepad.leftTrigger.value,
            rightTrigger: gamepad.rightTrigger.value
        )

        let identifier = ObjectIdentifier(controller)
        let previous = pressedInputs[identifier] ?? []
        let pressed = current.subtracting(previous)
        let released = previous.subtracting(current)
        if current.contains(.menu), pressed.contains(.buttonB) {
            NotificationCenter.default.post(name: .borealControllerQuickMenu, object: nil)
        }
        if let newest = pressed.first {
            lastInput = newest
            pressed.forEach { input in
                NotificationCenter.default.post(name: .borealControllerInputPressed, object: input)
            }
        }
        guard isMappingEnabled, activeApplications.values.contains(true) else {
            pressedInputs[identifier] = current
            return
        }
        pressed.forEach { postKey(for: $0, isDown: true) }
        released.forEach { postKey(for: $0, isDown: false) }
        pressedInputs[identifier] = current
    }

    private func postKey(for input: ControllerInput, isDown: Bool) {
        guard let keyCode = mapping[input].keyCode,
              let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func releaseInputs(for controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        (pressedInputs.removeValue(forKey: identifier) ?? []).forEach { postKey(for: $0, isDown: false) }
    }

    private func releaseAllInputs() {
        let allPressed = pressedInputs.values.reduce(into: Set<ControllerInput>()) { $0.formUnion($1) }
        allPressed.forEach { postKey(for: $0, isDown: false) }
        pressedInputs.removeAll()
    }

    private func refreshControllers() {
        controllers = GCController.controllers().enumerated().map { index, controller in
            let name = controller.vendorName ?? "Game controller"
            return DetectedController(
                id: "\(name)-\(controller.productCategory)-\(index)",
                name: name,
                category: controller.productCategory,
                supportsExtendedProfile: controller.extendedGamepad != nil
            )
        }
        if controllers.isEmpty { liveState = .idle }
    }

    private func saveMapping() {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        UserDefaults.standard.set(data, forKey: "controllerMapping")
    }
}
