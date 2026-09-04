import CoreGraphics
import Foundation

nonisolated enum ControllerInput: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case buttonA, buttonB, buttonX, buttonY
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case menu, options, leftThumbstickButton, rightThumbstickButton
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case leftStickUp, leftStickDown, leftStickLeft, leftStickRight
    case rightStickUp, rightStickDown, rightStickLeft, rightStickRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .buttonA: "A / Cross"
        case .buttonB: "B / Circle"
        case .buttonX: "X / Square"
        case .buttonY: "Y / Triangle"
        case .leftShoulder: "Left shoulder"
        case .rightShoulder: "Right shoulder"
        case .leftTrigger: "Left trigger"
        case .rightTrigger: "Right trigger"
        case .menu: "Menu / Start"
        case .options: "Options / Select"
        case .leftThumbstickButton: "Left stick click"
        case .rightThumbstickButton: "Right stick click"
        case .dpadUp: "D-pad up"
        case .dpadDown: "D-pad down"
        case .dpadLeft: "D-pad left"
        case .dpadRight: "D-pad right"
        case .leftStickUp: "Left stick up"
        case .leftStickDown: "Left stick down"
        case .leftStickLeft: "Left stick left"
        case .leftStickRight: "Left stick right"
        case .rightStickUp: "Right stick up"
        case .rightStickDown: "Right stick down"
        case .rightStickLeft: "Right stick left"
        case .rightStickRight: "Right stick right"
        }
    }
}

nonisolated enum ControllerKey: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case none, escape, returnKey, space, tab
    case up, down, left, right
    case w, a, s, d, q, e, r, f, z, x, c, v
    case shift, control, option, command
    case one, two, three, four

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "Unmapped"
        case .escape: "Escape"
        case .returnKey: "Return"
        case .space: "Space"
        case .tab: "Tab"
        case .up: "Up arrow"
        case .down: "Down arrow"
        case .left: "Left arrow"
        case .right: "Right arrow"
        case .shift: "Shift"
        case .control: "Control"
        case .option: "Option / Alt"
        case .command: "Command"
        default: rawValue.uppercased()
        }
    }

    var keyCode: CGKeyCode? {
        switch self {
        case .none: nil
        case .a: 0
        case .s: 1
        case .d: 2
        case .f: 3
        case .w: 13
        case .e: 14
        case .r: 15
        case .z: 6
        case .x: 7
        case .c: 8
        case .v: 9
        case .q: 12
        case .one: 18
        case .two: 19
        case .three: 20
        case .four: 21
        case .returnKey: 36
        case .tab: 48
        case .space: 49
        case .escape: 53
        case .command: 55
        case .shift: 56
        case .option: 58
        case .control: 59
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
        }
    }
}

nonisolated struct ControllerMapping: Codable, Hashable, Sendable {
    var bindings: [ControllerInput: ControllerKey]
    var stickDeadZone: Float

    static let standard = ControllerMapping(
        bindings: [
            .buttonA: .space, .buttonB: .escape, .buttonX: .e, .buttonY: .q,
            .leftShoulder: .z, .rightShoulder: .c,
            .leftTrigger: .control, .rightTrigger: .shift,
            .menu: .returnKey, .options: .tab,
            .dpadUp: .up, .dpadDown: .down, .dpadLeft: .left, .dpadRight: .right,
            .leftStickUp: .w, .leftStickDown: .s, .leftStickLeft: .a, .leftStickRight: .d
        ],
        stickDeadZone: 0.55
    )

    subscript(_ input: ControllerInput) -> ControllerKey {
        get { bindings[input] ?? .none }
        set { bindings[input] = newValue }
    }
}

nonisolated struct DetectedController: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: String
    let supportsExtendedProfile: Bool

    var family: ControllerFamily {
        let descriptor = "\(name) \(category)".lowercased()
        if descriptor.contains("dualsense") || descriptor.contains("dualshock") || descriptor.contains("playstation") || descriptor.contains("sony") { return .playStation }
        if descriptor.contains("xbox") || descriptor.contains("microsoft") { return .xbox }
        if descriptor.contains("joy-con") || descriptor.contains("nintendo") || descriptor.contains("switch") { return .nintendo }
        return .generic
    }
}

nonisolated enum ControllerFamily: String, Sendable {
    case playStation = "PlayStation"
    case xbox = "Xbox"
    case nintendo = "Nintendo"
    case generic = "Generic"
}

nonisolated struct ControllerLiveState: Equatable, Sendable {
    var pressedInputs: Set<ControllerInput> = []
    var leftStickX: Float = 0
    var leftStickY: Float = 0
    var rightStickX: Float = 0
    var rightStickY: Float = 0
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0

    static let idle = ControllerLiveState()

    func isPressed(_ input: ControllerInput) -> Bool { pressedInputs.contains(input) }
}

nonisolated enum ControllerDetectionState: Sendable {
    case unavailable
    case unsupported
    case ready

    var symbol: String { "gamecontroller.fill" }
}

nonisolated enum ControllerWineSupport {
    static func applyingEnvironment(to values: [String: String]) -> [String: String] {
        var result = values
        result["SDL_JOYSTICK_HIDAPI"] = "1"
        result["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"] = "1"
        return result
    }
}
