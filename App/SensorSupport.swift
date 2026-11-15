import SwiftUI
import AVFoundation
import UIKit

@MainActor
final class CameraAccess: ObservableObject {
    @Published var status = AVCaptureDevice.authorizationStatus(for: .video)
    func request(_ completion: @escaping (Bool) -> Void) {
        status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized { completion(true) }
        else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                DispatchQueue.main.async {
                    self.status = AVCaptureDevice.authorizationStatus(for: .video)
                    completion(allowed)
                }
            }
        } else { completion(false) }
    }
    func refresh() { status = AVCaptureDevice.authorizationStatus(for: .video) }
}

struct SensorNotice: View {
    let supported: Bool
    let permission: AVAuthorizationStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("SENSOR MODE · ESTIMATED REAL GEOMETRY", systemImage: "camera.metering.center.weighted")
                .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Palette.amber)
            if !supported {
                Text("This sensor is unavailable on this device. Training remains available in the mode picker.")
            } else if permission == .denied || permission == .restricted {
                Text("Camera access is unavailable. Training and previously captured rooms remain usable.")
                if permission == .denied {
                    Button("Open camera settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } else {
                Text("Geometry is an estimate in meters, separate from simulated mission content. Scan slowly in a well-lit room.")
            }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExportSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
