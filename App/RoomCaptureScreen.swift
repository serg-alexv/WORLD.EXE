import SwiftUI
import RoomPlan

struct RoomCaptureScreen: UIViewRepresentable {
    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }
    func updateUIView(_ view: RoomCaptureView, context: Context) {}
    static func dismantleUIView(_ view: RoomCaptureView, coordinator: ()) {
        view.captureSession.stop()
    }
}
