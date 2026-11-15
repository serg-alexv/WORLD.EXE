import SwiftUI
import ARKit
import SceneKit
import AVFoundation
import EvidenceCore

struct LiDARView: View {
    var evidence: EvidenceStore? = nil
    @StateObject private var camera = CameraAccess()
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var running = false
    @State private var status = "Stopped. Start requests camera access and begins live reconstruction."
    private var supported: Bool {
        ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("LIVE LiDAR MESH").font(.system(.headline, design: .monospaced))
                SensorNotice(supported: supported, permission: camera.status)
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Palette.panel)
                    if running {
                        LiveMeshView(status: $status, failed: { running = false }, evidence: evidence)
                    } else {
                        Label("Live sensor paused", systemImage: "viewfinder").foregroundStyle(.secondary)
                    }
                }.frame(height: 350).clipShape(RoundedRectangle(cornerRadius: 16))
                Text(status).font(.caption).accessibilityIdentifier("lidarStatus")
                HStack {
                    Button(running ? "Pause LiDAR" : "Start LiDAR") {
                        if running { running = false; status = "Paused. Live mesh released." }
                        else {
                            camera.request { allowed in
                                guard allowed, visible, scenePhase == .active else {
                                    status = "Camera access was not granted or the app is inactive."
                                    return
                                }
                                running = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent).disabled(!supported)
                    .accessibilityIdentifier("startLidar")
                }
                Text("Wireframe surfaces come from ARKit mesh anchors. Each start begins a fresh live session. At most 128 mesh chunks are displayed; this view does not save or export meshes.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; running = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { running = false; status = "Paused while app is inactive." }
            else { camera.refresh() }
        }
    }
}

struct LiveMeshView: UIViewRepresentable {
    @Binding var status: String
    let failed: () -> Void
    var evidence: EvidenceStore? = nil
    func makeCoordinator() -> Coordinator { Coordinator(status: $status, failed: failed, evidence: evidence) }
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.preferredFramesPerSecond = 30
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.planeDetection = [.horizontal, .vertical]
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        DispatchQueue.main.async { status = "Starting live reconstruction. Move slowly to establish tracking." }
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) {}
    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        coordinator.invalidate()
        view.session.pause()
        view.session.delegate = nil
        view.delegate = nil
        view.scene = SCNScene()
    }
    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        private let status: Binding<String>
        private let failed: () -> Void
        private let lock = NSLock()
        private var chunks: Set<UUID> = []
        private var valid = true
        private weak var evidence: EvidenceStore?
        private let captureID = UUID()
        private var lastEvidenceTime = -Double.greatestFiniteMagnitude
        init(status: Binding<String>, failed: @escaping () -> Void, evidence: EvidenceStore?) {
            self.evidence = evidence
            self.status = status
            self.failed = failed
        }
        func invalidate() { lock.lock(); valid = false; lock.unlock() }
        private func publish(_ message: String, failure: Bool = false, quality: TrackingQuality? = nil) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let active = self.valid
                self.lock.unlock()
                guard active else { return }
                if let quality { self.evidence?.recordTracking(id: self.captureID, quality: quality) }
                self.status.wrappedValue = message
                if failure { self.failed() }
            }
        }
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            update(node, anchor: anchor)
        }
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            update(node, anchor: anchor)
        }
        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            lock.lock(); chunks.remove(anchor.identifier); lock.unlock()
        }
        private func update(_ node: SCNNode, anchor: ARAnchor) {
            guard let anchor = anchor as? ARMeshAnchor else { return }
            lock.lock()
            let allowed = valid && (chunks.contains(anchor.identifier) || chunks.count < 128)
            if allowed { chunks.insert(anchor.identifier) }
            lock.unlock()
            guard allowed else { return }
            let mesh = anchor.geometry
            guard mesh.vertices.count <= 50000, mesh.faces.count <= 100000,
                  mesh.faces.indexCountPerPrimitive == 3 else { return }
            let vertices = mesh.vertices
            // Copy only the referenced vertex range, not the entire backing GPU allocation.
            guard vertices.count > 0, vertices.stride >= 12, vertices.offset >= 0 else { return }
            let vertexBytes = (vertices.count - 1) * vertices.stride + 12
            guard vertexBytes <= vertices.buffer.length,
                  vertices.offset <= vertices.buffer.length - vertexBytes else { return }
            let source = SCNGeometrySource(
                data: Data(bytes: vertices.buffer.contents().advanced(by: vertices.offset), count: vertexBytes),
                semantic: .vertex, vectorCount: vertices.count,
                usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4,
                dataOffset: 0, dataStride: vertices.stride)
            let faces = mesh.faces
            guard faces.bytesPerIndex == 2 || faces.bytesPerIndex == 4 else { return }
            let indexBytes = faces.count * 3 * faces.bytesPerIndex
            guard indexBytes <= faces.buffer.length else { return }
            let element = SCNGeometryElement(
                data: Data(bytes: faces.buffer.contents(), count: indexBytes),
                primitiveType: .triangles, primitiveCount: faces.count, bytesPerIndex: faces.bytesPerIndex)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemTeal
            material.lightingModel = .constant
            material.fillMode = .lines
            material.isDoubleSided = true
            material.transparency = 0.75
            geometry.materials = [material]
            node.geometry = geometry
            let now = ProcessInfo.processInfo.systemUptime
            lock.lock(); let report = valid && now - lastEvidenceTime >= 1
            if report { lastEvidenceTime = now }; lock.unlock()
            if report {
                let vertexCount = vertices.count, triangleCount = faces.count, identifier = anchor.identifier
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lock.lock(); let live = self.valid; self.lock.unlock()
                    if live { self.evidence?.recordMesh(id: identifier, vertices: vertexCount, triangles: triangleCount) }
                }
            }
        }
        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .normal: publish("Tracking normal. Teal wireframe is live estimated LiDAR geometry.", quality: .normal)
            case .notAvailable: publish("Tracking unavailable. Pause and restart when the camera is clear.", quality: .unavailable)
            case .limited(let reason): publish("Tracking limited: \(String(describing: reason)). Move slowly in good light.", quality: .limited)
            }
        }
        func session(_ session: ARSession, didFailWithError error: Error) {
            expeditionLog.error("LiDAR session failed: \(error.localizedDescription, privacy: .public)")
            publish("LiDAR error: \(error.localizedDescription). You can restart or return to Training.", failure: true)
        }
        func sessionWasInterrupted(_ session: ARSession) { publish("LiDAR interrupted. Pause and restart to resume.") }
    }
}
