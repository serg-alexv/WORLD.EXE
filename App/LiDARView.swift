import SwiftUI
import ARKit
import RealityKit

struct LiDARView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.sceneReconstruction = .mesh
        view.debugOptions.insert(.showSceneUnderstanding)
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {}
}
