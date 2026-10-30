import SceneKit
import SwiftUI

/// SceneKit-backed, procedural controller model. Every named control is animated
/// from `ControllerLiveState`, so no external asset is required for live input.
struct Controller3DView: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        view.rendersContinuously = false
        context.coordinator.family = family
        context.coordinator.sceneView = view
        context.coordinator.apply(state, animated: false)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if context.coordinator.family != family {
            view.scene = ControllerSceneFactory.makeScene(family: family)
            context.coordinator.family = family
        }
        context.coordinator.apply(state, animated: !reduceMotion)
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
