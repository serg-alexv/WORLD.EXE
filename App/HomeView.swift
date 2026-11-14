import SwiftUI
import ARKit
import RoomPlan

struct HomeView: View {
    @State private var mode = 0
    var body: some View {
        ZStack(alignment: .top) {
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                if mode == 0 { LiDARView().ignoresSafeArea() }
                else { RoomCaptureScreen().ignoresSafeArea() }
                VStack(spacing: 12) {
                    Text("WORLD.EXE / GENESIS").font(.headline)
                    Text("IMPERIUM OF ECHOES").font(.caption.monospaced()).foregroundStyle(.cyan)
                    Picker("Sensor", selection: $mode) {
                        Text("LiDAR Mesh").tag(0)
                        Text("SpaceRoom").tag(1)
                    }.pickerStyle(.segmented)
                }
                .padding().background(.black.opacity(0.75)).foregroundStyle(.white)
            } else {
                Text("LiDAR-equipped iPhone Pro or iPad Pro required.")
                    .padding().foregroundStyle(.white)
            }
        }.background(.black).preferredColorScheme(.dark)
    }
}
