import Foundation
import Combine
import OSLog
import RoomPlan
import ARKit
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

private struct RoomArchiveRecord: Codable {
    let version: Int
    let id: UUID
    let processedAt: Date
    let source: String
    let units: String
}

// Capture controls and published state are confined to the main queue.
final class RoomCaptureModel: NSObject, ObservableObject {
    @Published private(set) var captureView: RoomCaptureView?
    @Published private(set) var scanning = false
    @Published private(set) var processing = false
    @Published private(set) var snapshot: RoomSnapshot?
    // Only a successful capture from THIS launch provides a spatially aligned AR handoff.
    @Published private(set) var contactSession: ARSession?
    @Published private(set) var contactGeneration: UUID?
    @Published private(set) var exportURLs: [URL] = []
    @Published var status = "Stopped. Start a room capture or view the saved archive."
    private let evidence: EvidenceStore?
    private var startedUptime: Double?
    var observationCaptureID: UUID? { activeArchive?.id }
    var observationCapturedAt: Date? { activeArchive?.processedAt }
    private var activeArchive: RoomArchiveRecord?
    private var captureToken = UUID()
    private var captureRelay: RoomCaptureRelay?
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorldEXE-Room", isDirectory: true)
    }
    private var manifestURL: URL { directory.appendingPathComponent("current.json") }
    private func archiveDirectory(_ id: UUID) -> URL {
        directory.appendingPathComponent("captures", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }
    private func exports(in folder: URL) -> [URL] {
        ["capture-metadata.json", "captured-room.json", "captured-room.usdz"].map { folder.appendingPathComponent($0) }
    }
    init(evidence: EvidenceStore? = nil) {
        self.evidence = evidence
        super.init()
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(RoomArchiveRecord.self, from: Data(contentsOf: manifestURL))
            guard record.version == 1, record.units == "m", record.source == "Apple RoomPlan" else {
                throw CocoaError(.coderReadCorrupt)
            }
            let folder = archiveDirectory(record.id)
            let restored = try JSONDecoder().decode(RoomSnapshot.self, from: Data(contentsOf: folder.appendingPathComponent("room-view-v1.json")))
            guard restored.isValid, exports(in: folder).allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                throw CocoaError(.coderReadCorrupt)
            }
            activeArchive = record; snapshot = restored; exportURLs = exports(in: folder)
            evidence?.recordRoom(id: record.id, date: record.processedAt, elements: restored.elements.count, origin: .restoredArchive)
            status = "Local room archive restored. Estimated geometry is ready for isometric viewing."
            removeOrphans(keeping: record.id)
        } catch {
            status = "Saved room archive could not be read. Reset scan or start a new capture."
            expeditionLog.error("Room restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard RoomCaptureSession.isSupported, !scanning, !processing else { return }
        contactSession?.pause(); contactSession = nil; contactGeneration = nil
        releaseCaptureView()
        let view = RoomCaptureView(frame: .zero)
        let relay = RoomCaptureRelay(owner: self, token: captureToken)
        captureRelay = relay; view.delegate = relay; captureView = view
        scanning = true
        startedUptime = ProcessInfo.processInfo.systemUptime
        status = "Scanning. Slowly reveal walls, floor, doors and furniture. Press Stop to process."
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        expeditionLog.info("Room capture started")
    }
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard scanning else { return }
        scanning = false; processing = true
        status = "Capture stopped. RoomPlan is processing the estimated room."
        captureView?.captureSession.stop(pauseARSession: true)
    }
    func reset() {
        dispatchPrecondition(condition: .onQueue(.main))
        contactSession?.pause(); contactSession = nil; contactGeneration = nil
        releaseCaptureView(); scanning = false; processing = false
        activeArchive = nil; snapshot = nil; exportURLs = []
        do {
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                try FileManager.default.removeItem(at: manifestURL)
            }
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            status = "Room archive reset. Training progress is unchanged."
        } catch {
            status = "Archive cleared from memory, but deleting a saved file failed: \(error.localizedDescription). Try Reset again."
        }
    }
    private func releaseCaptureView() {
        captureToken = UUID()
        captureView?.delegate = nil
        captureView?.captureSession.stop(pauseARSession: true)
        captureView = nil; captureRelay = nil
    }
    fileprivate func receiveError(_ error: Error, token: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard token == captureToken else { return }
        fail(error)
    }
    fileprivate func receive(_ result: CapturedRoom, error: Error?, token: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard token == captureToken, processing || scanning else { return }
        if let error { fail(error); return }
        scanning = false; processing = false
        let nextSnapshot = RoomSnapshot(room: result)
        guard nextSnapshot.isValid else {
            status = "No usable room or too many elements (limit 512). The last archive is retained."
            releaseCaptureView(); return
        }
        let preservedSession = captureView?.captureSession.arSession
        releaseCaptureView()
        if persist(result, snapshot: nextSnapshot) {
            contactSession = preservedSession
            contactGeneration = preservedSession == nil ? nil : UUID()
        }
    }
    private func fail(_ error: Error) {
        if let startedUptime { evidence?.recordTelemetry(.captureDuration(seconds: ProcessInfo.processInfo.systemUptime - startedUptime, outcome: .failed)) }
        startedUptime = nil
        scanning = false; processing = false
        status = "Room capture error: \(error.localizedDescription). The last completed archive is retained."
        releaseCaptureView()
        expeditionLog.error("Room capture failed: \(error.localizedDescription, privacy: .public)")
    }
    private func persist(_ room: CapturedRoom, snapshot nextSnapshot: RoomSnapshot) -> Bool {
        let record = RoomArchiveRecord(version: 1, id: UUID(), processedAt: Date(), source: "Apple RoomPlan", units: "m")
        let folder = archiveDirectory(record.id)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: folder) } }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var localDirectory = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try localDirectory.setResourceValues(values)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(nextSnapshot).write(to: folder.appendingPathComponent("room-view-v1.json"), options: .atomic)
            try encoder.encode(room).write(to: folder.appendingPathComponent("captured-room.json"), options: .atomic)
            try room.export(to: folder.appendingPathComponent("captured-room.usdz"), exportOptions: .parametric)
            encoder.dateEncodingStrategy = .iso8601
            let metadata = try encoder.encode(record)
            try metadata.write(to: folder.appendingPathComponent("capture-metadata.json"), options: .atomic)
            // Immutable capture files are complete before the one atomic publication operation.
            try metadata.write(to: manifestURL, options: .atomic)
            committed = true
            activeArchive = record; snapshot = nextSnapshot; exportURLs = exports(in: folder)
            evidence?.recordRoom(id: record.id, date: record.processedAt, elements: nextSnapshot.elements.count, origin: .localSensor)
            if let startedUptime { evidence?.recordTelemetry(.captureDuration(seconds: ProcessInfo.processInfo.systemUptime - startedUptime, outcome: .succeeded)) }
            startedUptime = nil
            status = "Room processed and saved locally. Isometric view, metadata, JSON and USDZ are ready."
            removeOrphans(keeping: record.id)
            expeditionLog.info("Room archive saved: \(nextSnapshot.elements.count) elements")
            return true
        } catch {
            status = "New room could not be saved: \(error.localizedDescription). The previous complete archive is retained."
            expeditionLog.error("Room export failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    private func removeOrphans(keeping id: UUID) {
        let captures = directory.appendingPathComponent("captures", isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            if let candidate = UUID(uuidString: folder.lastPathComponent), candidate != id {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }
}

// Each view delegate carries its immutable capture token; stale results cannot replace a newer scan.
@objc(WorldEXERoomCaptureRelay)
private final class RoomCaptureRelay: NSObject, RoomCaptureViewDelegate {
    weak var owner: RoomCaptureModel?
    let token: UUID
    init(owner: RoomCaptureModel, token: UUID) {
        self.owner = owner; self.token = token
        super.init()
    }
    // RoomCaptureViewDelegate inherits NSCoding. Only the immutable token is encoded;
    // a restored relay is deliberately detached from any live camera session.
    required init?(coder: NSCoder) {
        guard let saved = coder.decodeObject(of: NSUUID.self, forKey: "captureToken") else { return nil }
        token = saved as UUID
        super.init()
    }
    func encode(with coder: NSCoder) {
        coder.encode(token as NSUUID, forKey: "captureToken")
    }
    func captureView(shouldPresent data: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            let token = self.token
            DispatchQueue.main.async { [weak owner] in owner?.receiveError(error, token: token) }
            return false
        }
        return true
    }
    func captureView(didPresent result: CapturedRoom, error: Error?) {
        let token = self.token
        DispatchQueue.main.async { [weak owner] in owner?.receive(result, error: error, token: token) }
    }
}
