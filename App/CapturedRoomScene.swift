import SwiftUI
import SceneKit
import simd

struct CapturedRoomScene: UIViewRepresentable {
    let snapshot: RoomSnapshot
    let zoom: Double
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor(red: 0.025, green: 0.045, blue: 0.075, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        context.coordinator.build(snapshot, in: view)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.camera.camera?.orthographicScale = context.coordinator.baseScale / max(0.1, zoom)
    }
    final class Coordinator {
        let camera = SCNNode()
        var baseScale = 10.0
        func build(_ snapshot: RoomSnapshot, in view: SCNView) {
            let scene = SCNScene()
            let root = SCNNode()
            scene.rootNode.addChildNode(root)
            guard snapshot.isValid else { view.scene = scene; return }
            for element in snapshot.elements {
                let d = element.dimensions
                // RoomPlan surfaces can have zero thickness. Render 2 cm only for visibility.
                let box = SCNBox(width: CGFloat(max(0.02, d[0])), height: CGFloat(max(0.02, d[1])),
                                 length: CGFloat(max(0.02, d[2])), chamferRadius: 0)
                let material = SCNMaterial()
                material.isDoubleSided = true
                material.lightingModel = .constant
                switch element.kind {
                case "wall": material.diffuse.contents = UIColor(red: 0.24, green: 0.49, blue: 0.53, alpha: 1)
                case "door", "opening": material.diffuse.contents = UIColor.systemOrange
                case "window": material.diffuse.contents = UIColor.systemCyan
                default: material.diffuse.contents = UIColor(red: 0.5, green: 0.42, blue: 0.62, alpha: 1)
                }
                material.transparency = element.kind == "wall" ? 0.38 : 0.75
                box.materials = [material]
                let node = SCNNode(geometry: box)
                let t = element.transform
                node.simdTransform = simd_float4x4(columns: (
                    SIMD4(t[0], t[1], t[2], t[3]), SIMD4(t[4], t[5], t[6], t[7]),
                    SIMD4(t[8], t[9], t[10], t[11]), SIMD4(t[12], t[13], t[14], t[15])))
                root.addChildNode(node)
            }
            let bounds = root.boundingBox
            let center = SCNVector3((bounds.min.x + bounds.max.x) / 2,
                                    (bounds.min.y + bounds.max.y) / 2,
                                    (bounds.min.z + bounds.max.z) / 2)
            let size = max(bounds.max.x - bounds.min.x, max(bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z))
            let radius = max(Float(2), size * 1.4)
            baseScale = Double(radius * 1.5)
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = baseScale
            camera.camera?.zNear = 0.01
            camera.camera?.zFar = Double(radius * 10 + 100)
            camera.position = SCNVector3(center.x + radius, center.y + radius, center.z + radius)
            camera.look(at: center)
            scene.rootNode.addChildNode(camera)
            view.scene = scene
            view.pointOfView = camera
        }
    }
}
