import SwiftUI
import RoomPlan
import AVFoundation

struct RoomCaptureScreen: View {
    @ObservedObject var model: RoomCaptureModel
    @StateObject private var camera = CameraAccess()
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var showIsometric = false
    @State private var sharing = false
    @State private var zoom = 1.0
    private var supported: Bool { RoomCaptureSession.isSupported }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ROOM / SPATIAL ARCHIVE").font(.system(.headline, design: .monospaced))
                SensorNotice(supported: supported, permission: camera.status)
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Palette.panel)
                    if showIsometric, let snapshot = model.snapshot {
                        CapturedRoomScene(snapshot: snapshot, zoom: zoom)
                    } else if let captureView = model.captureView {
                        RoomCaptureHost(model: model).id(ObjectIdentifier(captureView))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "cube.transparent").font(.largeTitle)
                            Text(model.snapshot == nil ? "No completed room capture" : "Saved room is ready for isometric viewing")
                                .font(.caption)
                        }.foregroundStyle(.secondary).padding()
                    }
                }.frame(height: 350).clipShape(RoundedRectangle(cornerRadius: 16))
                Text(model.status).font(.caption).accessibilityIdentifier("roomStatus")
                if model.processing { ProgressView("Processing captured room…").font(.caption) }
                HStack {
                    Button("Start") {
                        camera.request { allowed in
                            guard allowed, visible, scenePhase == .active else {
                                model.status = "Camera access was not granted or the app is inactive."
                                return
                            }
                            showIsometric = false
                            model.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!supported || model.scanning || model.processing)
                    .accessibilityIdentifier("startRoomScan")
                    Button("Stop") { model.stop() }.buttonStyle(.bordered)
                        .disabled(!model.scanning).accessibilityIdentifier("stopRoomScan")
                    Button("Reset scan", role: .destructive) {
                        model.reset(); showIsometric = false; zoom = 1
                    }.buttonStyle(.bordered).accessibilityIdentifier("resetRoomScan")
                }
                if let snapshot = model.snapshot {
                    Text("ESTIMATED ROOM · \(snapshot.elements.count) elements · meters")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Palette.amber)
                    Button(showIsometric ? "Hide isometric room" : "View captured room in isometric") {
                        model.stop()
                        showIsometric.toggle()
                    }.disabled(model.scanning || model.processing).accessibilityIdentifier("viewCapturedRoom")
                    if showIsometric {
                        HStack {
                            Text("Zoom").font(.caption)
                            Slider(value: $zoom, in: 0.5...2).accessibilityLabel("Captured room zoom")
                            Button("Reset camera") { zoom = 1 }.font(.caption)
                        }
                    }
                }
                Button("Share JSON / USDZ") { sharing = true }
                    .buttonStyle(.bordered).disabled(model.exportURLs.isEmpty || model.processing || model.scanning)
                    .accessibilityIdentifier("shareRoom")
                Text("Stop finishes capture and lets RoomPlan process it. The isometric archive preserves the captured element transforms and dimensions; it contains no game tiles. Start replaces the live session; the last completed archive remains until a new capture succeeds or Reset scan is pressed.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
        .sheet(isPresented: $sharing) { ExportSheet(urls: model.exportURLs) }
        .onAppear { visible = true }
        .onDisappear { visible = false; model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.stop() }
            else { camera.refresh() }
        }
    }
}

struct RoomCaptureHost: UIViewRepresentable {
    @ObservedObject var model: RoomCaptureModel
    func makeUIView(context: Context) -> UIView { model.captureView ?? UIView() }
    func updateUIView(_ view: UIView, context: Context) {}
    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        // The model retains the capture view until RoomPlan finishes processing.
        (view as? RoomCaptureView)?.captureSession.stop(pauseARSession: true)
    }
}
