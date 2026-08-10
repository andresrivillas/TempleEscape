import SwiftUI
import SceneKit

/// Bridges the SceneKit game world into SwiftUI.
struct SceneView: UIViewRepresentable {
    let viewModel: GameViewModel

    func makeUIView(context: Context) -> SCNView {
        let scene = GameScene()
        scene.viewModel = viewModel
        viewModel.attach(scene)

        let scnView = SCNView()
        scnView.scene = scene
        scnView.backgroundColor = UIColor.black
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.isPlaying = true
        scnView.delegate = scene
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.rendersContinuously = true

        scene.scnView = scnView
        scene.setupWorld()
        scene.setupGestures(on: scnView)
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
