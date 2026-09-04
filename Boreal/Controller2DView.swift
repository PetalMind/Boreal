import SwiftUI

/// An illustration of a real controller model with live input highlights.
struct Controller2DView: View {
    let family: ControllerFamily
    let state: ControllerLiveState

    private var layout: ControllerArtworkLayout {
        switch family {
        case .playStation: .dualSense
        case .xbox: .xboxSeries
        case .nintendo: .nintendoPro
        case .generic: .generic
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / layout.size.width, proxy.size.height / layout.size.height)
            ZStack {
                Image(layout.assetName).resizable().scaledToFit()
                if family == .playStation { dualSenseControls }
                analog(state.leftTrigger, at: layout.leftTrigger)
                analog(state.rightTrigger, at: layout.rightTrigger)
                capsule(.leftShoulder, at: layout.leftShoulder)
                capsule(.rightShoulder, at: layout.rightShoulder)
                circle(.dpadUp, at: layout.dpadUp)
                circle(.dpadDown, at: layout.dpadDown)
                circle(.dpadLeft, at: layout.dpadLeft)
                circle(.dpadRight, at: layout.dpadRight)
                circle(.buttonA, at: layout.buttonA)
                circle(.buttonB, at: layout.buttonB)
                circle(.buttonX, at: layout.buttonX)
                circle(.buttonY, at: layout.buttonY)
                capsule(.options, at: layout.options)
                capsule(.menu, at: layout.menu)
                stick(.leftThumbstickButton, x: state.leftStickX, y: state.leftStickY, at: layout.leftStick)
                stick(.rightThumbstickButton, x: state.rightStickX, y: state.rightStickY, at: layout.rightStick)
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .scaleEffect(scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live input on \(layout.modelName)")
    }

    /// The source artwork keeps these controls in sprite sheets so they can be
    /// animated independently. Compose their idle frames over the real shell.
    private var dualSenseControls: some View {
        Group {
            sprite("DualSenseButtons", source: CGSize(width: 224, height: 112), crop: CGRect(x: 0, y: 0, width: 55, height: 55), at: layout.buttonA)
            sprite("DualSenseButtons", source: CGSize(width: 224, height: 112), crop: CGRect(x: 57, y: 0, width: 55, height: 55), at: layout.buttonB)
            sprite("DualSenseButtons", source: CGSize(width: 224, height: 112), crop: CGRect(x: 113, y: 0, width: 55, height: 55), at: layout.buttonX)
            sprite("DualSenseButtons", source: CGSize(width: 224, height: 112), crop: CGRect(x: 169, y: 0, width: 55, height: 55), at: layout.buttonY)

            sprite("DualSenseDPad", source: CGSize(width: 179, height: 104), crop: CGRect(x: 37, y: 0, width: 37, height: 52), at: layout.dpadUp)
            sprite("DualSenseDPad", source: CGSize(width: 179, height: 104), crop: CGRect(x: 0, y: 0, width: 37, height: 52), at: layout.dpadDown)
            sprite("DualSenseDPad", source: CGSize(width: 179, height: 104), crop: CGRect(x: 75, y: 0, width: 52, height: 40), at: layout.dpadLeft)
            sprite("DualSenseDPad", source: CGSize(width: 179, height: 104), crop: CGRect(x: 127, y: 0, width: 52, height: 40), at: layout.dpadRight)

            sprite("DualSenseSticks", source: CGSize(width: 286, height: 94), crop: CGRect(x: 0, y: 0, width: 94, height: 94), at: layout.leftStick)
            sprite("DualSenseSticks", source: CGSize(width: 286, height: 94), crop: CGRect(x: 0, y: 0, width: 94, height: 94), at: layout.rightStick)
        }
    }

    private func sprite(_ asset: String, source: CGSize, crop: CGRect, at frame: CGRect) -> some View {
        GeometryReader { _ in
            Image(asset)
                .resizable()
                .frame(width: source.width, height: source.height)
                .position(x: source.width / 2 - crop.minX, y: source.height / 2 - crop.minY)
        }
        .frame(width: crop.width, height: crop.height)
        .clipped()
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private func circle(_ input: ControllerInput, at frame: CGRect) -> some View {
        let active = state.isPressed(input)
        return Circle().fill(active ? Color.cyan.opacity(0.68) : .clear)
            .overlay(Circle().stroke(active ? Color.white.opacity(0.9) : .clear, lineWidth: 3))
            .shadow(color: active ? .cyan : .clear, radius: 14)
            .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            .scaleEffect(active ? 0.9 : 1).animation(.easeOut(duration: 0.06), value: active)
    }

    private func capsule(_ input: ControllerInput, at frame: CGRect) -> some View {
        let active = state.isPressed(input)
        return Capsule().fill(active ? Color.cyan.opacity(0.68) : .clear)
            .overlay(Capsule().stroke(active ? Color.white.opacity(0.9) : .clear, lineWidth: 3))
            .shadow(color: active ? .cyan : .clear, radius: 14)
            .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            .animation(.easeOut(duration: 0.06), value: active)
    }

    private func analog(_ value: Float, at frame: CGRect) -> some View {
        let active = value > 0.03
        return RoundedRectangle(cornerRadius: frame.width * 0.22)
            .fill(active ? Color.cyan.opacity(0.3 + Double(value) * 0.5) : .clear)
            .overlay(RoundedRectangle(cornerRadius: frame.width * 0.22).stroke(active ? Color.cyan : .clear, lineWidth: 3))
            .shadow(color: active ? .cyan : .clear, radius: 14)
            .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            .animation(.easeOut(duration: 0.06), value: value)
    }

    private func stick(_ click: ControllerInput, x: Float, y: Float, at frame: CGRect) -> some View {
        let active = state.isPressed(click) || abs(x) > 0.08 || abs(y) > 0.08
        return Circle().fill(active ? Color.cyan.opacity(0.48) : .clear)
            .overlay(Circle().stroke(active ? Color.cyan : .clear, lineWidth: 4))
            .shadow(color: active ? .cyan : .clear, radius: 16)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX + CGFloat(x) * frame.width * 0.13, y: frame.midY - CGFloat(y) * frame.height * 0.13)
            .scaleEffect(state.isPressed(click) ? 0.88 : 1).animation(.easeOut(duration: 0.06), value: state)
    }
}

private struct ControllerArtworkLayout {
    let assetName: String; let modelName: String; let size: CGSize
    let leftTrigger, rightTrigger, leftShoulder, rightShoulder: CGRect
    let dpadUp, dpadDown, dpadLeft, dpadRight: CGRect
    let buttonA, buttonB, buttonX, buttonY, options, menu, leftStick, rightStick: CGRect

    static let dualSense = ControllerArtworkLayout(
        assetName: "DualSenseController", modelName: "DualSense controller", size: CGSize(width: 1200, height: 698),
        leftTrigger: .init(x: 299, y: 38, width: 99, height: 91), rightTrigger: .init(x: 802, y: 38, width: 99, height: 91),
        leftShoulder: .init(x: 263, y: 130, width: 165, height: 37), rightShoulder: .init(x: 772, y: 130, width: 165, height: 37),
        dpadUp: .init(x: 330, y: 220, width: 37, height: 52), dpadDown: .init(x: 330, y: 294, width: 37, height: 52),
        dpadLeft: .init(x: 286, y: 263, width: 52, height: 40), dpadRight: .init(x: 359, y: 263, width: 52, height: 40),
        buttonA: .init(x: 820, y: 316, width: 55, height: 55), buttonB: .init(x: 878, y: 257, width: 55, height: 55),
        buttonX: .init(x: 762, y: 257, width: 55, height: 55), buttonY: .init(x: 820, y: 200, width: 55, height: 55),
        options: .init(x: 393, y: 165, width: 30, height: 43), menu: .init(x: 777, y: 165, width: 30, height: 43),
        leftStick: .init(x: 422, y: 348, width: 94, height: 94), rightStick: .init(x: 692, y: 348, width: 94, height: 94))

    static let xboxSeries = ControllerArtworkLayout(
        assetName: "XboxOneController", modelName: "Xbox Wireless Controller", size: CGSize(width: 1534, height: 954),
        leftTrigger: .init(x: 235, y: 0, width: 190, height: 120), rightTrigger: .init(x: 1110, y: 0, width: 190, height: 120),
        leftShoulder: .init(x: 190, y: 105, width: 330, height: 70), rightShoulder: .init(x: 1015, y: 105, width: 330, height: 70),
        dpadUp: .init(x: 520, y: 550, width: 72, height: 88), dpadDown: .init(x: 520, y: 675, width: 72, height: 88),
        dpadLeft: .init(x: 450, y: 620, width: 88, height: 72), dpadRight: .init(x: 575, y: 620, width: 88, height: 72),
        buttonA: .init(x: 1120, y: 465, width: 115, height: 115), buttonB: .init(x: 1230, y: 355, width: 115, height: 115),
        buttonX: .init(x: 1015, y: 355, width: 115, height: 115), buttonY: .init(x: 1120, y: 250, width: 115, height: 115),
        options: .init(x: 610, y: 375, width: 78, height: 78), menu: .init(x: 845, y: 375, width: 78, height: 78),
        leftStick: .init(x: 255, y: 325, width: 195, height: 195), rightStick: .init(x: 875, y: 550, width: 195, height: 195))

    static let nintendoPro = ControllerArtworkLayout(
        assetName: "NintendoProController", modelName: "Nintendo Switch Pro Controller", size: CGSize(width: 1485, height: 1079),
        leftTrigger: .init(x: 155, y: 0, width: 250, height: 90), rightTrigger: .init(x: 1080, y: 0, width: 250, height: 90),
        leftShoulder: .init(x: 145, y: 70, width: 330, height: 75), rightShoulder: .init(x: 1010, y: 70, width: 330, height: 75),
        dpadUp: .init(x: 480, y: 440, width: 72, height: 100), dpadDown: .init(x: 480, y: 570, width: 72, height: 100),
        dpadLeft: .init(x: 405, y: 515, width: 100, height: 72), dpadRight: .init(x: 535, y: 515, width: 100, height: 72),
        buttonA: .init(x: 1192, y: 287, width: 112, height: 112), buttonB: .init(x: 1075, y: 400, width: 112, height: 112),
        buttonX: .init(x: 1075, y: 180, width: 112, height: 112), buttonY: .init(x: 960, y: 287, width: 112, height: 112),
        options: .init(x: 525, y: 190, width: 70, height: 70), menu: .init(x: 890, y: 190, width: 70, height: 70),
        leftStick: .init(x: 235, y: 245, width: 195, height: 195), rightStick: .init(x: 835, y: 450, width: 195, height: 195))

    static let generic = ControllerArtworkLayout(
        assetName: "GenericController", modelName: "Generic game controller", size: CGSize(width: 413.229, height: 298.403),
        leftTrigger: .init(x: 55, y: 10, width: 55, height: 30), rightTrigger: .init(x: 303, y: 10, width: 55, height: 30),
        leftShoulder: .init(x: 42, y: 38, width: 80, height: 24), rightShoulder: .init(x: 291, y: 38, width: 80, height: 24),
        dpadUp: .init(x: 105, y: 130, width: 20, height: 30), dpadDown: .init(x: 105, y: 175, width: 20, height: 30),
        dpadLeft: .init(x: 82, y: 153, width: 30, height: 20), dpadRight: .init(x: 118, y: 153, width: 30, height: 20),
        buttonA: .init(x: 320, y: 165, width: 28, height: 28), buttonB: .init(x: 345, y: 140, width: 28, height: 28),
        buttonX: .init(x: 295, y: 140, width: 28, height: 28), buttonY: .init(x: 320, y: 115, width: 28, height: 28),
        options: .init(x: 170, y: 125, width: 28, height: 18), menu: .init(x: 215, y: 125, width: 28, height: 18),
        leftStick: .init(x: 135, y: 200, width: 48, height: 48), rightStick: .init(x: 235, y: 200, width: 48, height: 48))
}
