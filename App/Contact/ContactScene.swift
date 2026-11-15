import SwiftUI
import SceneKit
import simd
import WorldCore

extension ContactGlyph {
    var title: String { switch self { case .circle: return "Круг"; case .triangle: return "Треугольник"; case .diamond: return "Ромб" } }
    var mark: String { switch self { case .circle: return "○"; case .triangle: return "△"; case .diamond: return "◇" } }
}
enum ContactArt {
    static let teal = UIColor(red: 0.25, green: 0.90, blue: 0.81, alpha: 1)
    static let amber = UIColor(red: 1, green: 0.73, blue: 0.32, alpha: 1)
    static func material(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial(); m.diffuse.contents = color; m.emission.contents = color.withAlphaComponent(0.24); m.lightingModel = .constant; return m
    }
    static func label(_ text: String) -> SCNNode {
        let g = SCNText(string: text, extrusionDepth: 0.1); g.font = .systemFont(ofSize: 16, weight: .bold)
        g.flatness = 0.5; g.materials = [material(teal)]
        let n = SCNNode(geometry: g); n.scale = SCNVector3(0.003,0.003,0.003)
        n.eulerAngles.x = -.pi / 2; n.position = SCNVector3(-0.018,0.055,0.02); n.name = "label"; return n
    }
    static func game() -> SCNNode {
        let group = SCNNode(), capsule = SCNNode(); capsule.name = "capsule"
        let shell = SCNCylinder(radius: 0.055, height: 0.13); shell.materials = [material(teal)]
        let body = SCNNode(geometry: shell); body.position.y = 0.075; capsule.addChildNode(body)
        let dome = SCNSphere(radius: 0.055); dome.segmentCount = 16; dome.materials = [material(amber)]
        let top = SCNNode(geometry: dome); top.name = "capsuleLid"; top.position.y = 0.14; capsule.addChildNode(top); group.addChildNode(capsule)
        for i in 0..<3 {
            let g = SCNCylinder(radius: 0.04, height: 0.03); g.radialSegmentCount = 16; g.materials = [material(.darkGray)]
            let n = SCNNode(geometry: g); n.name = "node\(i)"; n.simdPosition = ContactMath.offsets[i] + SIMD3(0,0.02,0)
            n.addChildNode(label(String(i+1))); group.addChildNode(n)
            let link = SCNBox(width: 0.008, height: 0.004, length: CGFloat(simd_length(ContactMath.offsets[i])), chamferRadius: 0)
            link.materials = [material(teal.withAlphaComponent(0.35))]; let line = SCNNode(geometry: link)
            line.simdPosition = ContactMath.offsets[i] / 2 + SIMD3(0,0.004,0); line.eulerAngles.y = atan2(ContactMath.offsets[i].x,ContactMath.offsets[i].z)
            group.addChildNode(line)
        }
        return group
    }
    static func update(_ root: SCNNode, state: ContactPublicState, glyphs: [ContactGlyph?]? = nil) {
        if let lid = root.childNode(withName: "capsuleLid", recursively: true) {
            let height: Float = state.phase == .active ? 0.14 : 0.23
            if abs(lid.position.y - height) > 0.001 {
                SCNTransaction.begin(); SCNTransaction.animationDuration = 0.35
                lid.position.y = height
                lid.geometry?.firstMaterial?.diffuse.contents = state.phase == .complete ? UIColor.white : teal
                SCNTransaction.commit()
            }
        }
        for i in 0..<3 {
            guard let n = root.childNode(withName: "node\(i)", recursively: false) else { continue }
            let color: UIColor = state.isStable(i) ? teal : state.poweredNode == i ? amber : .darkGray
            n.geometry?.firstMaterial?.diffuse.contents = color
            let text = glyphs.flatMap { $0.count == 3 ? $0[i]?.mark : nil } ?? String(i+1)
            if let label = n.childNode(withName: "label", recursively: false)?.geometry as? SCNText, label.string as? String != text { label.string = text }
        }
    }
    static func surfaces(_ room: ContactRoomDTO, into parent: SCNNode) {
        for s in room.surfaces {
            let d = s.dimensions; let g = SCNBox(width: CGFloat(max(0.02,d[0])), height: CGFloat(max(0.02,d[1])), length: CGFloat(max(0.02,d[2])), chamferRadius: 0)
            let m = material(s.kind == "wall" ? teal : UIColor(red: 0.28,green: 0.36,blue: 0.45,alpha: 1))
            m.isDoubleSided = true; m.transparency = s.kind == "wall" ? 0.22 : 0.6; g.materials = [m]
            let n = SCNNode(geometry: g); n.simdTransform = ContactMath.matrix(s.transform); parent.addChildNode(n)
        }
    }
}
struct ContactMapView: UIViewRepresentable {
    let room: ContactRoomDTO
    let state: ContactPublicState
    let root: [Float]?
    let zoom: Double
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(); v.backgroundColor = UIColor(red: 0.025,green: 0.045,blue: 0.075,alpha: 1)
        v.antialiasingMode = .multisampling4X; v.preferredFramesPerSecond = 30; v.isAccessibilityElement = true
        v.accessibilityLabel = "Изометрическая карта: комната, капсула и три пронумерованных узла без символов"
        return v
    }
    func updateUIView(_ view: SCNView, context: Context) { context.coordinator.update(view, room: room, state: state, placement: root, zoom: zoom) }
    final class Coordinator {
        private var session: UUID?
        private let camera = SCNNode()
        private var game = SCNNode()
        private var framedPlacement = false
        private var scale = 3.0
        func update(_ view: SCNView, room: ContactRoomDTO, state: ContactPublicState, placement: [Float]?, zoom: Double) {
            if session != state.session {
                session = state.session; framedPlacement = false; let scene = SCNScene()
                ContactArt.surfaces(room, into: scene.rootNode); game = ContactArt.game(); scene.rootNode.addChildNode(game)
                camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true; camera.camera?.zNear = 0.01
                scene.rootNode.addChildNode(camera); view.scene = scene; view.pointOfView = camera; frame(room, placement)
            }
            game.isHidden = placement == nil
            if let placement { game.simdTransform = ContactMath.matrix(placement); if !framedPlacement { frame(room, placement); framedPlacement = true } }
            ContactArt.update(game, state: state); camera.camera?.orthographicScale = scale / max(0.5,min(3,zoom))
        }
        private func frame(_ room: ContactRoomDTO, _ placement: [Float]?) {
            var (lo,hi) = room.bounds
            if let placement {
                let m = ContactMath.matrix(placement)
                for p in [SIMD3<Float>(0,0.2,0)] + ContactMath.offsets {
                    let w = m * SIMD4(p.x,p.y,p.z,1); let v = SIMD3(w.x,w.y,w.z)
                    lo = simd_min(lo,v - SIMD3(repeating: 0.08)); hi = simd_max(hi,v + SIMD3(repeating: 0.08))
                }
            }
            let center = (lo+hi)/2, span = max(1,simd_length(hi-lo)); scale = Double(span * 1.25)
            camera.simdPosition = center + SIMD3(repeating: span); camera.look(at: SCNVector3(center.x,center.y,center.z))
            camera.camera?.zFar = Double(span * 8 + 10)
        }
    }
}
