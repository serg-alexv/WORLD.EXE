import Foundation
import Combine
import OSLog
import RoomPlan
import simd

struct RoomSnapshot: Codable {
    struct Element: Codable {
        let kind: String
        let dimensions: [Float]
        let transform: [Float]
    }
    let version: Int
    let elements: [Element]
    init(room: CapturedRoom) {
        version = 1
        func element(_ kind: String, _ dimensions: SIMD3<Float>, _ matrix: simd_float4x4) -> Element {
            Element(kind: kind, dimensions: [dimensions.x, dimensions.y, dimensions.z],
                    transform: [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
                        .flatMap { [$0.x, $0.y, $0.z, $0.w] })
        }
        elements = room.floors.map { element("floor", $0.dimensions, $0.transform) }
            + room.walls.map { element("wall", $0.dimensions, $0.transform) }
            + room.doors.map { element("door", $0.dimensions, $0.transform) }
            + room.windows.map { element("window", $0.dimensions, $0.transform) }
            + room.openings.map { element("opening", $0.dimensions, $0.transform) }
            + room.objects.map { element("object", $0.dimensions, $0.transform) }
    }
    var isValid: Bool {
        version == 1 && !elements.isEmpty && elements.count <= 512 && elements.allSatisfy {
            $0.dimensions.count == 3 && $0.transform.count == 16 &&
            $0.dimensions.allSatisfy { $0.isFinite && $0 >= 0 && $0 < 1000 } &&
            $0.transform.allSatisfy { $0.isFinite && abs($0) < 10000 }
        }
    }
}

// Delegate entry points remain nonisolated for Swift 5 SDK compatibility.
// Every published mutation and capture control operation is dispatched to the main queue.
final class RoomCaptureModel: NSObject, ObservableObject, RoomCaptureViewDelegate {
    @Published private(set) var captureView: RoomCaptureView?
    @Published private(set) var scanning = false
    @Published private(set) var processing = false
    @Published private(set) var snapshot: RoomSnapshot?
    @Published private(set) var exportURLs: [URL] = []
    @Published var status = "Stopped. Start a room capture or view the saved archive."
    private var capturedRoom: CapturedRoom?
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorldEXE-Room", isDirectory: true)
    }
    private var snapshotURL: URL { directory.appendingPathComponent("room-view-v1.json") }
    private var jsonURL: URL { directory.appendingPathComponent("captured-room.json") }
    private var usdzURL: URL { directory.appendingPathComponent("captured-room.usdz") }
    override init() {
        super.init()
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return }
        do {
            let restored = try JSONDecoder().decode(RoomSnapshot.self, from: Data(contentsOf: snapshotURL))
            guard restored.isValid else { throw CocoaError(.coderReadCorrupt) }
            snapshot = restored
            refreshExports()
            status = "Local room archive restored. Estimated geometry is ready for isometric viewing."
        } catch {
            status = "Saved room archive could not be read. Reset scan or start a new capture."
            expeditionLog.error("Room restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard RoomCaptureSession.isSupported, !scanning, !processing else { return }
        releaseCaptureView()
        let view = RoomCaptureView(frame: .zero)
        view.delegate = self
        captureView = view
        scanning = true
        status = "Scanning. Slowly reveal walls, floor, doors and furniture. Press Stop to process."
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        expeditionLog.info("Room capture started")
    }
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard scanning else { return }
        scanning = false
        processing = true
        status = "Capture stopped. RoomPlan is processing the estimated room."
        captureView?.captureSession.stop(pauseARSession: true)
    }
    func reset() {
        dispatchPrecondition(condition: .onQueue(.main))
        releaseCaptureView()
        scanning = false
        processing = false
        capturedRoom = nil
        snapshot = nil
        exportURLs = []
        do {
            for url in [snapshotURL, jsonURL, usdzURL] where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            status = "Room archive reset. Training progress is unchanged."
        } catch {
            status = "Archive cleared from memory, but deleting a saved file failed: \(error.localizedDescription). Try Reset again."
            expeditionLog.error("Room reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    private func releaseCaptureView() {
        captureView?.delegate = nil
        captureView?.captureSession.stop(pauseARSession: true)
        captureView = nil
    }
    private func refreshExports() {
        exportURLs = [jsonURL, usdzURL].filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            DispatchQueue.main.async { self.fail(error) }
            return false
        }
        return true
    }
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async {
            if let error { self.fail(error); return }
            guard self.processing || self.scanning else { return }
            self.scanning = false
            self.processing = false
            let snapshot = RoomSnapshot(room: processedResult)
            guard snapshot.isValid else {
                self.status = "No usable room or too many elements (limit 512). Start again and scan a single room."
                self.releaseCaptureView()
                return
            }
            self.capturedRoom = processedResult
            self.snapshot = snapshot
            self.releaseCaptureView()
            self.persist(processedResult, snapshot: snapshot)
        }
    }
    private func fail(_ error: Error) {
        scanning = false
        processing = false
        status = "Room capture error: \(error.localizedDescription). The last completed archive is retained."
        releaseCaptureView()
        expeditionLog.error("Room capture failed: \(error.localizedDescription, privacy: .public)")
    }
    private func persist(_ room: CapturedRoom, snapshot: RoomSnapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var localDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try localDirectory.setResourceValues(values)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
            try encoder.encode(room).write(to: jsonURL, options: .atomic)
            // Remove an old export before attempting a new one so sharing cannot mix captures.
            if FileManager.default.fileExists(atPath: usdzURL.path) {
                try FileManager.default.removeItem(at: usdzURL)
            }
            try room.export(to: usdzURL, exportOptions: .parametric)
            refreshExports()
            status = "Room processed and saved locally. Isometric view, JSON and USDZ are ready."
            expeditionLog.info("Room archive saved: \(snapshot.elements.count) elements")
        } catch {
            refreshExports()
            status = "Room available in memory. Archive/export error: \(error.localizedDescription). Available files can still be shared."
            expeditionLog.error("Room export failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
