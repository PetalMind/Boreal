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
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = false
        context.coordinator.sceneView = view
        context.coordinator.install(scene: ControllerSceneFactory.makeScene(family: family), family: family)
        context.coordinator.apply(state, animated: false)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if context.coordinator.family != family {
            context.coordinator.install(scene: ControllerSceneFactory.makeScene(family: family), family: family)
        }
        context.coordinator.apply(state, animated: !reduceMotion)
    }

    final class Coordinator {
        weak var sceneView: SCNView?
        var family: ControllerFamily?
        private var previousState: ControllerLiveState?
        private var controls: [ControllerInput: SCNNode] = [:]
        private var leftStick: SCNNode?
        private var rightStick: SCNNode?

        func install(scene: SCNScene, family: ControllerFamily) {
            sceneView?.scene = scene
            self.family = family
            previousState = nil
            controls = Dictionary(
                uniqueKeysWithValues: ControllerInput.allCases.compactMap { input in
                    scene.rootNode.childNode(withName: input.rawValue, recursively: true).map { (input, $0) }
                })
            leftStick = scene.rootNode.childNode(withName: "leftStick", recursively: true)
            rightStick = scene.rootNode.childNode(withName: "rightStick", recursively: true)
        }

        func apply(_ state: ControllerLiveState, animated: Bool) {
            guard sceneView?.scene != nil, previousState != state else { return }
            previousState = state
            let duration = animated ? BorealMotion.inputDuration : 0
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration

            for input in ControllerInput.allCases {
                guard let node = controls[input] else { continue }
                let pressed = state.isPressed(input)
                node.geometry?.firstMaterial?.emission.contents = pressed ? NSColor.systemCyan : NSColor.black
                node.geometry?.firstMaterial?.emission.intensity = pressed ? 1.15 : 0
                node.scale = pressed ? SCNVector3(0.88, 0.72, 0.88) : SCNVector3(1, 1, 1)
            }

            moveStick(leftStick, x: state.leftStickX, y: state.leftStickY, pressed: state.isPressed(.leftThumbstickButton))
            moveStick(rightStick, x: state.rightStickX, y: state.rightStickY, pressed: state.isPressed(.rightThumbstickButton))
            moveTrigger(controls[.leftTrigger], value: state.leftTrigger)
            moveTrigger(controls[.rightTrigger], value: state.rightTrigger)
            SCNTransaction.commit()
        }

        private func moveStick(_ node: SCNNode?, x: Float, y: Float, pressed: Bool) {
            guard let node else { return }
            node.position.x = CGFloat(x) * 0.22
            node.position.z = CGFloat(-y) * 0.22
            node.position.y = pressed ? 0.35 : 0.42
            node.eulerAngles = SCNVector3(CGFloat(-y) * 0.18, 0, CGFloat(-x) * 0.18)
        }

        private func moveTrigger(_ node: SCNNode?, value: Float) {
            guard let node else { return }
            node.eulerAngles.x = -0.18 - CGFloat(value) * 0.35
            node.geometry?.firstMaterial?.emission.contents = value > 0.03 ? NSColor.systemCyan : NSColor.black
            node.geometry?.firstMaterial?.emission.intensity = CGFloat(value)
        }
    }
}
