import Foundation
import Combine
import UIKit
import EvidenceCore

/// Main-queue adapter. This object never changes a mission, AR session or model.
/// Disk work is serialized; bounded snapshots are written at most once per second.
final class EvidenceStore: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    @Published var recording = true
    @Published private(set) var status = "Локальная запись: три независимых журнала."
    private var journal = try! EvidenceJournal(capacityPerLane: 128)
    private let clock = try! EvidenceClock(monotonicOrigin: ProcessInfo.processInfo.systemUptime)
    private let io = DispatchQueue(label: "org.worldexe.evidence.disk", qos: .utility)
    private var pending: DispatchWorkItem?
    private let persist: Bool
    private let folder: URL
    private var lastMesh = -Double.greatestFiniteMagnitude
    var snapshot: EvidenceSnapshot { journal.snapshot }
    var previousURL: URL { folder.appendingPathComponent("previous-session.json") }

    init(persist: Bool = true) {
        self.persist = persist
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(persist ? "Evidence" : "Evidence-CI", isDirectory: true)
        if persist {
            let root = folder
            io.async {
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    var local = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
                    try local.setResourceValues(values)
                    let current = root.appendingPathComponent("current-session.json"), previous = root.appendingPathComponent("previous-session.json")
                    if FileManager.default.fileExists(atPath: current.path) {
                        let data = try Data(contentsOf: current)
                        _ = try EvidenceSnapshot.decode(data)
                        try data.write(to: previous, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                } catch { DispatchQueue.main.async { [weak self] in self?.status = "Предыдущий журнал не прочитан. Текущие события доступны отдельно." } }
            }
        }
    }
    private func stamp() throws -> EvidenceStamp {
        dispatchPrecondition(condition: .onQueue(.main))
        guard journal.lastSequence < .max else { throw EvidenceError.staleSequence }
        return try EvidenceStamp(session: journal.session, sequence: journal.lastSequence + 1,
                                 recordedAt: Date(), elapsedSeconds: clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
    }
    private func changed() {
        revision &+= 1
        guard persist, pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.pending = nil; self?.flush() }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
    private func rejected() { status = "Запись отклонена: некорректные данные. Нули вместо неизвестных значений не подставлены." }
    func recordRoom(id: UUID, date: Date?, elements: Int, origin: ObservationOrigin) {
        guard recording else { return }
        do {
            try journal.append(ObservationRecord(stamp: stamp(), source: .roomPlan, origin: origin,
                                                  captureID: id, capturedAt: date, payload: .roomSummary(elements: elements)))
            changed()
        } catch { rejected() }
    }
    func recordTracking(id: UUID, quality: TrackingQuality, sensorElapsedSeconds: Double? = nil) {
        guard recording else { return }
        do {
            try journal.append(ObservationRecord(stamp: stamp(), source: .arkit, origin: .localSensor,
                                                  captureID: id, sensorElapsedSeconds: sensorElapsedSeconds, payload: .tracking(quality)))
            changed()
        } catch { rejected() }
    }
    func recordMesh(id: UUID, vertices: Int, triangles: Int) {
        guard recording else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMesh >= 1 else { return }
        do {
            try journal.append(ObservationRecord(stamp: stamp(), source: .arkit, origin: .localSensor,
                                                  captureID: id, payload: .meshSummary(vertices: vertices, triangles: triangles)))
            lastMesh = now; changed()
        } catch { rejected() }
    }
    func recordTelemetry(_ payload: TelemetryPayload) {
        guard recording else { return }
        do { try journal.append(TelemetryRecord(stamp: stamp(), payload: payload)); changed() }
        catch { rejected() }
    }
    func recordInference(sha: String, requested: BackendRequest, tokens: Int?, seconds: Double?, outcome: OperationOutcome) {
        do {
            let sample = try InferenceSample(modelSHA256: sha, requestedBackend: requested,
                                             confirmedBackend: nil, tokens: tokens, requestSeconds: seconds, outcome: outcome)
            recordTelemetry(.inference(sample))
        } catch { rejected() }
    }
    func recordGame(mission: UUID, kind: GameEventKind, action: String, revision: UInt32? = nil, score: Int? = nil) {
        guard recording else { return }
        do {
            try journal.append(GameEventRecord(stamp: stamp(), missionID: mission, kind: kind, action: action, revision: revision, score: score))
            changed()
        } catch { rejected() }
    }
    func clear(_ lane: EvidenceLane) {
        dispatchPrecondition(condition: .onQueue(.main))
        journal.clear(lane); changed(); flush()
        status = "Выбранный журнал очищен. Комната, модель и прогресс игры не изменены."
    }
    func flush() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard persist else { return }
        pending?.cancel(); pending = nil
        let snapshot = journal.snapshot, root = folder
        io.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try snapshot.encoded().write(to: root.appendingPathComponent("current-session.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch { DispatchQueue.main.async { self?.status = "Ошибка локального сохранения журнала. Экспорт текущего запуска можно повторить." } }
        }
    }
    func export(_ done: @escaping ([URL]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let value = journal.snapshot
        // One bounded export folder, not an accumulating sequence of private data files.
        let root = folder.appendingPathComponent("Export", isDirectory: true)
        io.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let files: [(String, Data)] = [("observations.json", try value.observationData()),
                                              ("telemetry.json", try value.telemetryData()),
                                              ("gameplay.json", try value.gameplayData()),
                                              ("session.json", try value.encoded())]
                for (name, data) in files { try data.write(to: root.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
                DispatchQueue.main.async { done(files.map { root.appendingPathComponent($0.0) }) }
            } catch { DispatchQueue.main.async { self?.status = "Не удалось подготовить экспорт. Повторите попытку."; done([]) } }
        }
    }
}
