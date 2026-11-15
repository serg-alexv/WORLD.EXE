import SwiftUI
import ARKit
import SceneKit
import Metal
import simd
import WorldCore
import EvidenceCore

struct ContactARView: UIViewRepresentable {
    let session: ARSession
    let room: ContactRoomDTO
    let state: ContactPublicState
    let glyphs: [ContactGlyph?]
    let anchor: ARAnchor?
    let active: Bool
    let canPlace: Bool
    let canTap: Bool
    let onTracking: (Bool, String) -> Void
    var evidence: EvidenceStore? = nil
    let onPlace: (ARAnchor) -> Void
    let onMove: ([Float]) -> Void
    let onTap: (Int?) -> Void
    let onNote: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(); view.session = session; view.scene = SCNScene(); view.preferredFramesPerSecond = 30
        view.automaticallyUpdatesLighting = false; view.accessibilityLabel = "Камера исследователя. Коснитесь свободного стола для размещения; затем узла для осмотра."
        let c = context.coordinator; c.view = view; view.session.delegate = c
        view.addGestureRecognizer(UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:))))
        configure(c); c.run(active); return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) { configure(context.coordinator); context.coordinator.run(active) }
    private func configure(_ c: Coordinator) {
        c.room = room; c.canPlace = canPlace; c.canTap = canTap; c.evidence = evidence
        c.tracked = onTracking; c.placed = onPlace; c.moved = onMove; c.tapped = onTap; c.note = onNote
        c.install(anchor); ContactArt.update(c.game, state: state, glyphs: glyphs)
    }
    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        coordinator.live = false; view.session.delegate = nil; view.delegate = nil; view.session.pause(); coordinator.view = nil
    }
    final class Coordinator: NSObject, ARSessionDelegate {
        weak var view: ARSCNView?
        weak var evidence: EvidenceStore?
        private let evidenceCapture = UUID()
        private var lastEvidenceQuality: TrackingQuality?
        var room: ContactRoomDTO?
        var canPlace = false, canTap = false, live = true
        var tracked: ((Bool,String) -> Void)?
        var placed: ((ARAnchor) -> Void)?
        var moved: (([Float]) -> Void)?
        var tapped: ((Int?) -> Void)?
        var note: ((String) -> Void)?
        var game = ContactArt.game()
        private var rootAnchor: ARAnchor?
        private var running = false, normal = false, interrupted = false, rootLost = false
        private var meshNodes: [UUID: SCNNode] = [:]
        private var lastSent = Date.distantPast
        private var sentTransform: [Float]?
        private let frameLock = NSLock()
        private var lastFrameTime: TimeInterval = -1
        private var evidenceFrameOrigin: TimeInterval?
        private var lastTrackingText = ""
        private let meshLock = NSLock()
        private var pendingMeshes: Set<UUID> = []
        private var knownMeshes: Set<UUID> = []
        func run(_ active: Bool) {
            guard let view, running != active else { return }; running = active
            if !active { view.session.pause(); normal = false; tracked?(false,"AR на паузе"); return }
            guard ARWorldTrackingConfiguration.isSupported else { running = false; tracked?(false,"AR недоступен"); return }
            let configuration = ARWorldTrackingConfiguration(); configuration.planeDetection = [.horizontal]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { configuration.sceneReconstruction = .mesh }
            view.session.run(configuration, options: [])
        }
        func install(_ anchor: ARAnchor?) {
            guard rootAnchor?.identifier != anchor?.identifier else { return }
            if let old = rootAnchor, anchor == nil { view?.session.remove(anchor: old) }
            game.removeFromParentNode(); game = ContactArt.game(); rootAnchor = anchor; rootLost = false; sentTransform = nil
            if let anchor { game.simdTransform = anchor.transform; view?.scene.rootNode.addChildNode(game) }
        }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard live, running, normal, !interrupted, !rootLost, let view else { note?("Дождитесь нормального отслеживания и подтвердите продолжение."); return }
            let point = gesture.location(in: view)
            if rootAnchor != nil {
                guard canTap else { note?("Игра на паузе. Оба игрока должны подтвердить продолжение."); return }
                for hit in view.hitTest(point, options: [.categoryBitMask: 1]) {
                    var n: SCNNode? = hit.node
                    while let candidate = n {
                        if candidate.name == "capsule" { tapped?(nil); return }
                        if let name = candidate.name, name.hasPrefix("node"), let i = Int(name.dropFirst(4)), (0..<3).contains(i) { tapped?(i); return }
                        n = candidate.parent
                    }
                }
                note?("Коснитесь виртуального узла или капсулы."); return
            }
            guard canPlace, let room, let frame = view.session.currentFrame,
                  let query = view.raycastQuery(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal),
                  let result = view.session.raycast(query).first, let plane = result.anchor as? ARPlaneAnchor, plane.alignment == .horizontal else {
                note?("Нужен свободный безопасный стол. Дождитесь плоскости и подтверждения обоих игроков."); return
            }
            let t = result.worldTransform, p = SIMD3(t.columns.3.x,t.columns.3.y,t.columns.3.z), camera = frame.camera.transform
            let c = SIMD3(camera.columns.3.x,camera.columns.3.y,camera.columns.3.z), forward = -SIMD3(camera.columns.2.x,camera.columns.2.y,camera.columns.2.z)
            let local = simd_inverse(plane.transform) * SIMD4(p.x,p.y,p.z,1), values = ContactMath.array(t)
            guard simd_distance(p,c) >= 0.55, simd_distance(p,c) <= 2, simd_dot(p-c,forward) > 0.1,
                  abs(local.x-plane.center.x) + 0.31 <= plane.extent.x/2,
                  abs(local.z-plane.center.z) + 0.31 <= plane.extent.z/2, room.contains(values) else {
                note?("Нужна свободная плоскость от 62×62 см внутри скана, перед камерой в 0,55–2 м. Не спешите и не тянитесь через препятствия."); return
            }
            let anchor = ARAnchor(name: "CONTACT", transform: t); install(anchor); view.session.add(anchor: anchor); placed?(anchor)
        }
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            frameLock.lock()
            if evidenceFrameOrigin == nil { evidenceFrameOrigin = frame.timestamp }
            let sensorElapsed = max(0, frame.timestamp - (evidenceFrameOrigin ?? frame.timestamp))
            let deliver = frame.timestamp - lastFrameTime >= 0.2
            if deliver { lastFrameTime = frame.timestamp }
            frameLock.unlock()
            guard deliver else { return }
            let normal: Bool, text: String
            let quality: TrackingQuality
            switch frame.camera.trackingState {
            case .normal: quality = .normal; normal = true; text = "Отслеживание: нормально"
            case .notAvailable: quality = .unavailable; normal = false; text = "Отслеживание недоступно"
            case .limited: quality = .limited; normal = false; text = "Отслеживание ограничено. Осмотритесь медленно; затем нажмите «Продолжить»."
            }
            let sensorTime = sensorElapsed
            DispatchQueue.main.async { [weak self] in
                guard let self, self.live, self.running else { return }
                if self.lastEvidenceQuality != quality {
                    self.lastEvidenceQuality = quality
                    self.evidence?.recordTracking(id: self.evidenceCapture, quality: quality, sensorElapsedSeconds: sensorTime)
                }
                let next = normal && !self.interrupted && !self.rootLost && self.running
                guard next != self.normal || text != self.lastTrackingText else { return }
                self.normal = next; self.lastTrackingText = text
                self.tracked?(next,text)
            }
        }
        func sessionWasInterrupted(_ session: ARSession) {
            DispatchQueue.main.async { [weak self] in guard let self, self.live else { return }; self.interrupted = true; self.normal = false; self.tracked?(false,"AR прерван. После восстановления подтвердите продолжение.") }
        }
        func sessionInterruptionEnded(_ session: ARSession) {
            DispatchQueue.main.async { [weak self] in guard let self, self.live else { return }; self.interrupted = false; self.normal = false; self.tracked?(false,"Восстановление AR. Требуется подтверждение продолжения.") }
        }
        func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async { [weak self] in self?.normal = false; self?.tracked?(false,"Ошибка AR. Вернитесь к сканированию комнаты.") }
        }
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { copy(anchors) }
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { copy(anchors) }
        private func copy(_ anchors: [ARAnchor]) {
            for anchor in anchors {
                let isMesh = anchor is ARMeshAnchor
                if isMesh {
                    meshLock.lock()
                    let allowed = !pendingMeshes.contains(anchor.identifier) && (knownMeshes.contains(anchor.identifier) || knownMeshes.count < 64)
                    if allowed { pendingMeshes.insert(anchor.identifier); knownMeshes.insert(anchor.identifier) }
                    meshLock.unlock()
                    if !allowed { continue }
                }
                let mesh = (anchor as? ARMeshAnchor).flatMap(Self.mesh)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    defer {
                        if isMesh {
                            self.meshLock.lock(); self.pendingMeshes.remove(anchor.identifier)
                            if mesh == nil { self.knownMeshes.remove(anchor.identifier) }
                            self.meshLock.unlock()
                        }
                    }
                    guard self.live, self.running, let view = self.view else { return }
                    if anchor.identifier == self.rootAnchor?.identifier {
                        self.rootAnchor = anchor; self.game.simdTransform = anchor.transform
                        let a = ContactMath.array(anchor.transform)
                        let changed = self.sentTransform.map { zip($0,a).contains { abs($0.0-$0.1) > 0.02 } } ?? true
                        if changed && Date().timeIntervalSince(self.lastSent) >= 1 {
                            self.sentTransform = a; self.lastSent = Date(); self.moved?(a)
                        }
                    }
                    guard let mesh, self.meshNodes[anchor.identifier] != nil || self.meshNodes.count < 64 else { return }
                    let g = SCNGeometry(sources: [SCNGeometrySource(vertices: mesh.0)], elements: [SCNGeometryElement(indices: mesh.1, primitiveType: .triangles)])
                    let m = SCNMaterial(); m.colorBufferWriteMask = []; m.writesToDepthBuffer = true; m.readsFromDepthBuffer = true; m.isDoubleSided = true; g.materials = [m]
                    let n = self.meshNodes[anchor.identifier] ?? SCNNode(); n.geometry = g; n.simdTransform = anchor.transform; n.renderingOrder = -1; n.categoryBitMask = 4
                    if n.parent == nil { view.scene.rootNode.addChildNode(n) }; self.meshNodes[anchor.identifier] = n
                }
            }
        }
        private static func mesh(_ anchor: ARMeshAnchor) -> ([SCNVector3],[UInt32])? {
            let v = anchor.geometry.vertices, f = anchor.geometry.faces
            guard v.format == .float3, v.count > 0, v.count <= 20000, v.stride >= 12, v.offset >= 0,
                  v.offset + (v.count-1)*v.stride + 12 <= v.buffer.length, f.indexCountPerPrimitive == 3,
                  f.count > 0, f.count <= 40000, [2,4].contains(f.bytesPerIndex), f.count*3*f.bytesPerIndex <= f.buffer.length else { return nil }
            let vertices: [SCNVector3] = (0..<v.count).map {
                let p = v.buffer.contents().advanced(by: v.offset + $0*v.stride)
                return SCNVector3(p.loadUnaligned(as: Float.self),p.advanced(by: 4).loadUnaligned(as: Float.self),p.advanced(by: 8).loadUnaligned(as: Float.self))
            }
            guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && abs($0.x) < 1000 && abs($0.y) < 1000 && abs($0.z) < 1000 }) else { return nil }
            let indices: [UInt32] = (0..<f.count*3).map {
                let p = f.buffer.contents().advanced(by: $0*f.bytesPerIndex)
                return f.bytesPerIndex == 2 ? UInt32(p.loadUnaligned(as: UInt16.self)) : p.loadUnaligned(as: UInt32.self)
            }
            guard indices.allSatisfy({ $0 < UInt32(v.count) }) else { return nil }; return (vertices,indices)
        }
        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.live else { return }
                for a in anchors {
                    self.meshLock.lock(); self.knownMeshes.remove(a.identifier); self.meshLock.unlock()
                    self.meshNodes.removeValue(forKey: a.identifier)?.removeFromParentNode()
                    if a.identifier == self.rootAnchor?.identifier { self.rootLost = true; self.normal = false; self.tracked?(false,"Якорь утрачен. Начните новую миссию.") }
                }
            }
        }
    }
}
