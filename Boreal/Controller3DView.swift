import SceneKit
import SwiftUI

/// SceneKit-backed, procedural controller model. Every named control is animated
/// from `ControllerLiveState`, so no external asset is required for live input.
struct Controller3DView: NSViewRepresentable {
    let family: ControllerFamily
    let state: ControllerLiveState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = ControllerSceneFactory.makeScene(family: family)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        context.coordinator.sceneView = view
        context.coordinator.apply(state, animated: false)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if context.coordinator.family != family {
            view.scene = ControllerSceneFactory.makeScene(family: family)
            context.coordinator.family = family
        }
        context.coordinator.apply(state, animated: true)
    }

    final class Coordinator {
        weak var sceneView: SCNView?
        var family: ControllerFamily?

        func apply(_ state: ControllerLiveState, animated: Bool) {
            guard let scene = sceneView?.scene else { return }
            let duration = animated ? 0.06 : 0
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration

            for input in ControllerInput.allCases {
                guard let node = scene.rootNode.childNode(withName: input.rawValue, recursively: true) else { continue }
                let pressed = state.isPressed(input)
                node.geometry?.firstMaterial?.emission.contents = pressed ? NSColor.systemCyan : NSColor.black
                node.geometry?.firstMaterial?.emission.intensity = pressed ? 1.15 : 0
                node.scale = pressed ? SCNVector3(0.88, 0.72, 0.88) : SCNVector3(1, 1, 1)
            }

            moveStick(scene, name: "leftStick", x: state.leftStickX, y: state.leftStickY, pressed: state.isPressed(.leftThumbstickButton))
            moveStick(scene, name: "rightStick", x: state.rightStickX, y: state.rightStickY, pressed: state.isPressed(.rightThumbstickButton))
            moveTrigger(scene, name: ControllerInput.leftTrigger.rawValue, value: state.leftTrigger)
            moveTrigger(scene, name: ControllerInput.rightTrigger.rawValue, value: state.rightTrigger)
            SCNTransaction.commit()
        }

        private func moveStick(_ scene: SCNScene, name: String, x: Float, y: Float, pressed: Bool) {
            guard let node = scene.rootNode.childNode(withName: name, recursively: true) else { return }
            node.position.x = CGFloat(x) * 0.22
            node.position.z = CGFloat(-y) * 0.22
            node.position.y = pressed ? 0.35 : 0.42
            node.eulerAngles = SCNVector3(CGFloat(-y) * 0.18, 0, CGFloat(-x) * 0.18)
        }

        private func moveTrigger(_ scene: SCNScene, name: String, value: Float) {
            guard let node = scene.rootNode.childNode(withName: name, recursively: true) else { return }
            node.eulerAngles.x = -0.18 - CGFloat(value) * 0.35
            node.geometry?.firstMaterial?.emission.contents = value > 0.03 ? NSColor.systemCyan : NSColor.black
            node.geometry?.firstMaterial?.emission.intensity = CGFloat(value)
        }
    }
}

private enum ControllerSceneFactory {
    static func makeScene(family: ControllerFamily) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let controller = SCNNode()
        controller.name = "controller"
        controller.eulerAngles = SCNVector3(-0.42, 0, 0)
        controller.position = SCNVector3(0, -0.15, 0)
        scene.rootNode.addChildNode(controller)

        addBody(to: controller, family: family)
        addControls(to: controller, family: family)
        addLighting(to: scene)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 36
        camera.camera?.wantsHDR = true
        camera.camera?.bloomIntensity = 0.15
        camera.position = SCNVector3(0, 5.8, 11.8)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        return scene
    }

    private static func addBody(to root: SCNNode, family: ControllerFamily) {
        let shell = family == .playStation ? NSColor(calibratedWhite: 0.88, alpha: 1) : NSColor(calibratedWhite: 0.12, alpha: 1)
        let inset = family == .playStation ? NSColor(calibratedWhite: 0.08, alpha: 1) : NSColor(calibratedWhite: 0.18, alpha: 1)

        let center = node(SCNBox(width: 5.8, height: 0.75, length: 2.75, chamferRadius: 0.72), color: shell)
        center.position.y = 0.05
        root.addChildNode(center)

        for side: CGFloat in [-1, 1] {
            let grip = node(SCNCapsule(capRadius: 0.82, height: 3.55), color: shell)
            grip.position = SCNVector3(side * 2.35, -0.75, 0.45)
            grip.eulerAngles = SCNVector3(0.36, 0, side * -0.34)
            root.addChildNode(grip)
        }

        let panel = node(SCNBox(width: family == .playStation ? 2.25 : 1.7, height: 0.18, length: 1.2, chamferRadius: 0.28), color: inset)
        panel.position = SCNVector3(0, 0.49, -0.22)
        root.addChildNode(panel)
    }

    private static func addControls(to root: SCNNode, family: ControllerFamily) {
        let face = family == .playStation ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.22, alpha: 1)
        addDPad(to: root, color: face)

        let labels = faceLabels(family)
        let positions: [(ControllerInput, CGFloat, CGFloat, String, NSColor)] = [
            (.buttonY, 2.05, -0.80, labels.0, .systemYellow),
            (.buttonX, 1.62, -0.37, labels.1, .systemBlue),
            (.buttonB, 2.48, -0.37, labels.2, .systemRed),
            (.buttonA, 2.05, 0.06, labels.3, .systemGreen)
        ]
        for (input, x, z, label, color) in positions {
            let button = cylinder(radius: 0.29, height: 0.2, color: face, name: input.rawValue)
            button.position = SCNVector3(x, 0.57, z)
            root.addChildNode(button)
            addText(label, color: family == .playStation ? .white : color, to: button)
        }

        addStick(to: root, name: "leftStick", clickName: ControllerInput.leftThumbstickButton.rawValue, x: family == .playStation ? -1.0 : -1.22, z: family == .playStation ? 0.30 : -0.18)
        addStick(to: root, name: "rightStick", clickName: ControllerInput.rightThumbstickButton.rawValue, x: family == .playStation ? 1.0 : 0.95, z: family == .playStation ? 0.30 : 0.35)

        addCenterButton(to: root, input: .menu, x: 0.54)
        addCenterButton(to: root, input: .options, x: -0.54)
        addShoulders(to: root, face: face)
    }

    private static func addDPad(to root: SCNNode, color: NSColor) {
        let directions: [(ControllerInput, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (.dpadUp, -2.05, -0.72, 0.36, 0.72), (.dpadDown, -2.05, 0, 0.36, 0.72),
            (.dpadLeft, -2.41, -0.36, 0.72, 0.36), (.dpadRight, -1.69, -0.36, 0.72, 0.36)
        ]
        for (input, x, z, width, length) in directions {
            let part = node(SCNBox(width: width, height: 0.2, length: length, chamferRadius: 0.09), color: color, name: input.rawValue)
            part.position = SCNVector3(x, 0.56, z)
            root.addChildNode(part)
        }
    }

    private static func addStick(to root: SCNNode, name: String, clickName: String, x: CGFloat, z: CGFloat) {
        let base = cylinder(radius: 0.47, height: 0.22, color: NSColor(calibratedWhite: 0.06, alpha: 1))
        base.position = SCNVector3(x, 0.48, z)
        root.addChildNode(base)
        let stick = cylinder(radius: 0.34, height: 0.25, color: NSColor(calibratedWhite: 0.17, alpha: 1), name: name)
        stick.position = SCNVector3(0, 0.42, 0)
        let clickSurface = cylinder(radius: 0.31, height: 0.04, color: NSColor(calibratedWhite: 0.22, alpha: 1), name: clickName)
        clickSurface.position.y = 0.14
        stick.addChildNode(clickSurface)
        base.addChildNode(stick)
    }

    private static func addCenterButton(to root: SCNNode, input: ControllerInput, x: CGFloat) {
        let button = node(SCNBox(width: 0.33, height: 0.13, length: 0.18, chamferRadius: 0.08), color: .darkGray, name: input.rawValue)
        button.position = SCNVector3(x, 0.55, -0.57)
        root.addChildNode(button)
    }

    private static func addShoulders(to root: SCNNode, face: NSColor) {
        for (side, shoulder, trigger) in [(-1.0, ControllerInput.leftShoulder, ControllerInput.leftTrigger), (1.0, .rightShoulder, .rightTrigger)] {
            let bumper = node(SCNBox(width: 1.5, height: 0.28, length: 0.52, chamferRadius: 0.18), color: face, name: shoulder.rawValue)
            bumper.position = SCNVector3(side * 1.78, 0.28, -1.47)
            root.addChildNode(bumper)
            let triggerNode = node(SCNBox(width: 1.15, height: 0.45, length: 0.72, chamferRadius: 0.2), color: .darkGray, name: trigger.rawValue)
            triggerNode.position = SCNVector3(side * 1.72, -0.05, -1.7)
            triggerNode.pivot = SCNMatrix4MakeTranslation(0, 0, -0.3)
            root.addChildNode(triggerNode)
        }
    }

    private static func faceLabels(_ family: ControllerFamily) -> (String, String, String, String) {
        switch family {
        case .playStation: ("△", "□", "○", "×")
        case .nintendo: ("X", "Y", "A", "B")
        case .xbox, .generic: ("Y", "X", "B", "A")
        }
    }

    private static func addText(_ text: String, color: NSColor, to parent: SCNNode) {
        let geometry = SCNText(string: text, extrusionDepth: 0.012)
        geometry.font = NSFont.systemFont(ofSize: 0.28, weight: .bold)
        geometry.flatness = 0.05
        geometry.firstMaterial?.diffuse.contents = color
        let label = SCNNode(geometry: geometry)
        let bounds = label.boundingBox
        label.position = SCNVector3(-CGFloat(bounds.max.x - bounds.min.x) / 2, 0.12, CGFloat(bounds.max.y - bounds.min.y) / 2)
        label.eulerAngles.x = -.pi / 2
        parent.addChildNode(label)
    }

    private static func addLighting(to scene: SCNScene) {
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .area; key.light?.intensity = 900; key.light?.color = NSColor(calibratedRed: 0.72, green: 0.92, blue: 1, alpha: 1); key.position = SCNVector3(-4, 7, 7); scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .omni; fill.light?.intensity = 520; fill.light?.color = NSColor(calibratedRed: 0.55, green: 0.48, blue: 1, alpha: 1); fill.position = SCNVector3(5, 2, 4); scene.rootNode.addChildNode(fill)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 260; ambient.light?.color = NSColor.white; scene.rootNode.addChildNode(ambient)
    }

    private static func cylinder(radius: CGFloat, height: CGFloat, color: NSColor, name: String? = nil) -> SCNNode {
        node(SCNCylinder(radius: radius, height: height), color: color, name: name)
    }

    private static func node(_ geometry: SCNGeometry, color: NSColor, name: String? = nil) -> SCNNode {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.metalness.contents = 0.28
        material.roughness.contents = 0.34
        geometry.materials = [material]
        let result = SCNNode(geometry: geometry)
        result.name = name
        return result
    }
}
