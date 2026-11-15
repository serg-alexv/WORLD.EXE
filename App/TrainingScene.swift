import SwiftUI
import SceneKit
import WorldCore

struct TrainingScene: UIViewRepresentable {
    @ObservedObject var game: GameStore
    let zoom: Double
    func makeCoordinator() -> Coordinator { Coordinator(game: game) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor(red: 0.025, green: 0.045, blue: 0.075, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = SpatialPerformanceBudget.targetFPS
        context.coordinator.build(view)
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        view.preferredFramesPerSecond = SpatialPerformanceBudget.targetFPS
        context.coordinator.update(zoom: zoom)
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.squad.removeAllActions()
        DispatchQueue.main.async { coordinator.game.finishMovement() }
        view.scene = nil
    }
    @MainActor
    final class Coordinator: NSObject {
        let game: GameStore
        weak var view: SCNView?
        let scene = SCNScene()
        let camera = SCNNode()
        let squad = SCNNode()
        let previewRoot = SCNNode()
        var previewNodes: [SCNNode] = []
        var previewTeal: SCNGeometry!
        var previewAmber: SCNGeometry!
        var lastPreview: [GridPoint] = []
        var lastAffordable: Bool?

        var relicNodes: [GridPoint: SCNNode] = [:]
        var lastPosition: GridPoint?
        let teal = UIColor(red: 0.25, green: 0.9, blue: 0.81, alpha: 1)
        let amber = UIColor(red: 1, green: 0.73, blue: 0.32, alpha: 1)
        init(game: GameStore) { self.game = game }
        func material(_ color: UIColor, glow: Bool = false) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.roughness.contents = 0.75
            if glow { material.emission.contents = color.withAlphaComponent(0.65) }
            return material
        }
        func location(_ point: GridPoint, height: Float = 0) -> SCNVector3 {
            SCNVector3(Float(point.x - 4) * 1.08, height, Float(point.y - 4) * 1.08)
        }
        func build(_ view: SCNView) {
            self.view = view
            view.scene = scene
            scene.rootNode.addChildNode(previewRoot)
            // One bounded pool, two shared immutable geometries: no node/material churn on updates.
            let good = SCNCylinder(radius: 0.11, height: 0.025)
            good.materials = [material(teal, glow: true)]
            let expensive = SCNCylinder(radius: 0.11, height: 0.025)
            expensive.materials = [material(amber, glow: true)]
            previewTeal = good; previewAmber = expensive
            // Grow only to the longest route actually shown; no unused 80-node preallocation.
            previewNodes.reserveCapacity(16)

            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = 15
            camera.camera?.zNear = 0.1
            camera.camera?.zFar = 100
            camera.position = SCNVector3(12, 12, 12)
            camera.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(camera)
            view.pointOfView = camera
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = UIColor(red: 0.40, green: 0.55, blue: 0.68, alpha: 1)
            scene.rootNode.addChildNode(ambient)
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .omni
            key.light?.intensity = 1100
            key.position = SCNVector3(-4, 12, 6)
            scene.rootNode.addChildNode(key)
            let sector = Sector.training
            for y in 0..<sector.height {
                for x in 0..<sector.width {
                    let point = GridPoint(x, y)
                    let tile = SCNNode(geometry: SCNBox(width: 1, height: 0.18, length: 1, chamferRadius: 0.06))
                    tile.name = "tile:\(x):\(y)"
                    tile.position = location(point, height: -0.12)
                    let shade: CGFloat = (x + y) % 2 == 0 ? 0.13 : 0.17
                    tile.geometry?.materials = [material(UIColor(red: shade * 0.65, green: shade, blue: shade * 1.25, alpha: 1))]
                    scene.rootNode.addChildNode(tile)
                    if sector.obstacles.contains(point) {
                        let height = CGFloat(0.9 + Double((x * 7 + y * 3) % 4) * 0.18)
                        let pillar = SCNNode(geometry: SCNBox(width: 0.78, height: height, length: 0.78, chamferRadius: 0.12))
                        pillar.position.y = Float(height / 2) + 0.12
                        pillar.geometry?.materials = [material(UIColor(red: 0.19, green: 0.23, blue: 0.30, alpha: 1))]
                        tile.addChildNode(pillar)
                        let cap = SCNNode(geometry: SCNBox(width: 0.48, height: 0.035, length: 0.48, chamferRadius: 0.02))
                        cap.position.y = Float(height / 2 + 0.02)
                        cap.geometry?.materials = [material(amber.withAlphaComponent(0.4), glow: true)]
                        pillar.addChildNode(cap)
                    }
                    if sector.relics.contains(point) {
                        let relic = SCNNode(geometry: SCNPyramid(width: 0.42, height: 0.8, length: 0.42))
                        relic.position.y = 0.55
                        relic.geometry?.materials = [material(amber, glow: true)]
                        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 5)
                        relic.runAction(.repeatForever(spin))
                        tile.addChildNode(relic)
                        relicNodes[point] = relic
                        let base = SCNNode(geometry: SCNCylinder(radius: 0.33, height: 0.12))
                        base.position.y = 0.18
                        base.geometry?.materials = [material(amber.withAlphaComponent(0.5))]
                        tile.addChildNode(base)
                    }
                    if point == sector.extraction {
                        let pad = SCNNode(geometry: SCNTorus(ringRadius: 0.38, pipeRadius: 0.045))
                        pad.position.y = 0.16
                        pad.geometry?.materials = [material(teal, glow: true)]
                        tile.addChildNode(pad)
                    }
                }
            }
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.24, pipeRadius: 0.04))
            ring.geometry?.materials = [material(teal, glow: true)]
            let core = SCNNode(geometry: SCNCone(topRadius: 0.05, bottomRadius: 0.17, height: 0.45))
            core.position.y = 0.23
            core.geometry?.materials = [material(teal, glow: true)]
            ring.addChildNode(core)
            ring.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.10, z: 0, duration: 0.8),
                .moveBy(x: 0, y: -0.10, z: 0, duration: 0.8)
            ])))
            squad.addChildNode(ring)
            squad.position = location(game.mission.position, height: 0.23)
            scene.rootNode.addChildNode(squad)
            lastPosition = game.mission.position
        }
        func update(zoom: Double) {
            camera.camera?.orthographicScale = 15 / max(0.1, zoom)
            for (point, node) in relicNodes { node.isHidden = game.mission.recovered.contains(point) }
            if lastPosition != game.mission.position {
                squad.removeAllActions()
                if game.moving, game.lastRoute.first == lastPosition {
                    let actions = game.lastRoute.dropFirst().map {
                        SCNAction.move(to: location($0, height: 0.23), duration: 0.18)
                    }
                    squad.runAction(.sequence(actions)) { [weak self] in
                        DispatchQueue.main.async { self?.game.finishMovement() }
                    }
                } else { squad.position = location(game.mission.position, height: 0.23) }
                lastPosition = game.mission.position
            }
            let route = game.mission.phase == .active ? (game.preview ?? []) : []
            let affordable = max(0, route.count - 1) <= game.mission.actions
            if route != lastPreview || lastAffordable != affordable {
                let count = max(0, route.count - 1)
                while previewNodes.count < count {
                    let node = SCNNode(geometry: previewTeal)
                    previewRoot.addChildNode(node)
                    previewNodes.append(node)
                }
                for index in previewNodes.indices {
                    let node = previewNodes[index]
                    node.isHidden = index >= count
                    if index < count {
                        node.position = location(route[index + 1], height: 0.025)
                        node.geometry = affordable ? previewTeal : previewAmber
                    }
                }
                lastPreview = route; lastAffordable = affordable
            }
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            for hit in view.hitTest(recognizer.location(in: view), options: nil) {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("tile:") {
                        let parts = name.split(separator: ":")
                        if parts.count == 3, let x = Int(parts[1]), let y = Int(parts[2]) {
                            game.select(GridPoint(x, y))
                            return
                        }
                    }
                    node = current.parent
                }
            }
        }
    }
}
