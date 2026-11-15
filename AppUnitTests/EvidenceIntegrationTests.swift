import XCTest
import Foundation
import WorldCore
import EvidenceCore
@testable import WorldEXE

@MainActor
final class EvidenceIntegrationTests: XCTestCase {
    func testTrainingNeverCreatesSensorEvidence() {
        let log = EvidenceStore(persist: false)
        let game = GameStore(persist: false, evidence: log)
        game.begin(); game.plotObjective(); game.confirmMove(); game.finishMovement(); game.endTurn()
        XCTAssertFalse(log.snapshot.gameplay.isEmpty)
        XCTAssertTrue(log.snapshot.observations.isEmpty)
        XCTAssertTrue(log.snapshot.telemetry.isEmpty)
    }
    func testContactDemoInspectionIsGameEventNotObservation() {
        let log = EvidenceStore(persist: false)
        let controller = ContactSessionController(evidence: log)
        controller.demo(); controller.act(.inspect(0))
        XCTAssertEqual(controller.state?.inspected, 1)
        XCTAssertEqual(log.snapshot.gameplay.count, 2)
        XCTAssertEqual(log.snapshot.gameplay.last?.action, "inspect:0")
        XCTAssertTrue(log.snapshot.observations.isEmpty)
        XCTAssertTrue(log.snapshot.telemetry.isEmpty)
        controller.close()
    }
    func testClearingJournalCannotResetMission() {
        let log = EvidenceStore(persist: false)
        let game = GameStore(persist: false, evidence: log); game.begin(); game.endTurn()
        let before = game.mission
        log.clear(.gameplay)
        XCTAssertEqual(game.mission, before)
        XCTAssertTrue(log.snapshot.gameplay.isEmpty)
    }
    func testPausingRecordingDoesNotStopGameplay() {
        let log = EvidenceStore(persist: false); log.recording = false
        let controller = ContactSessionController(evidence: log)
        controller.demo(); controller.act(.inspect(0))
        XCTAssertEqual(controller.state?.inspected, 1)
        XCTAssertTrue(log.snapshot.gameplay.isEmpty)
        controller.close()
    }
    func testInferenceTelemetryNeverCreatesModelObservation() {
        let log = EvidenceStore(persist: false)
        log.recordInference(sha: String(repeating: "f", count: 64), requested: .metal, tokens: 24, seconds: 3, outcome: .succeeded)
        XCTAssertEqual(log.snapshot.telemetry.count, 1)
        XCTAssertTrue(log.snapshot.observations.isEmpty); XCTAssertTrue(log.snapshot.gameplay.isEmpty)
        guard case .inference(let inference) = log.snapshot.telemetry[0].payload else { return XCTFail("Wrong lane") }
        XCTAssertNil(inference.confirmedBackend); XCTAssertEqual(inference.requestTokensPerSecond, 8)
    }
    func testAppJournalUsesRelativeElapsedTime() throws {
        let log = EvidenceStore(persist: false)
        log.recordRoom(id: UUID(), date: Date(), elements: 1, origin: .localSensor)
        let time = try XCTUnwrap(log.snapshot.observations.first?.stamp.elapsedSeconds)
        XCTAssertGreaterThanOrEqual(time, 0)
        XCTAssertLessThan(time, 5, "Time must be relative to this journal, not device uptime")
        let json = String(decoding: try log.snapshot.encoded(), as: UTF8.self)
        XCTAssertFalse(json.contains("uptime")); XCTAssertTrue(json.contains("elapsedSeconds"))
    }
    func testFailedInferenceKeepsUnknownValues() {
        let log = EvidenceStore(persist: false)
        log.recordInference(sha: String(repeating: "f", count: 64), requested: .cpu, tokens: nil, seconds: nil, outcome: .failed)
        guard let payload = log.snapshot.telemetry.first?.payload, case .inference(let s) = payload else { return XCTFail("Missing telemetry") }
        XCTAssertNil(s.tokens); XCTAssertNil(s.requestSeconds); XCTAssertNil(s.requestTokensPerSecond)
    }
    func testRestoredRoomUsesOriginalArchiveTime() {
        let log = EvidenceStore(persist: false), id = UUID(), old = Date(timeIntervalSince1970: 100)
        log.recordRoom(id: id, date: old, elements: 3, origin: .restoredArchive)
        XCTAssertEqual(log.snapshot.observations.first?.capturedAt, old)
        XCTAssertEqual(log.snapshot.observations.first?.captureID, id)
        XCTAssertNotEqual(log.snapshot.observations.first?.stamp.recordedAt, old)
    }
    func testDemoRoomCannotBeSentAsObservedWelcome() throws {
        let mission = ContactMission(seed: 4)
        var packet = ContactPacket(kind: .welcome, state: mission.state)
        packet.state = mission.state; packet.room = .demo
        XCTAssertThrowsError(try ContactPacket.decode(JSONEncoder().encode(packet)))
        XCTAssertNil(ContactRoomDTO.demo.captureID)
        XCTAssertNil(ContactRoomDTO.demo.capturedAt)
    }
    func testNetworkRejectsOversizedAndMalformedPackets() {
        XCTAssertThrowsError(try ContactPacket.decode(Data(repeating: 65, count: 262145)))
        XCTAssertThrowsError(try ContactPacket.decode(Data("{}".utf8)))
    }
    func testNetworkRejectsExtraFieldsAndWrongRevision() throws {
        let state = ContactMission(seed: 1).state
        var beat = ContactPacket(kind: .beat, state: state); beat.ready = true
        XCTAssertNoThrow(try ContactPacket.decode(JSONEncoder().encode(beat)))
        beat.state = state
        XCTAssertThrowsError(try ContactPacket.decode(JSONEncoder().encode(beat)))
        let command = ContactCommand(session: state.session, revision: state.revision, role: .researcher, action: .inspect(0))
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ContactPacket(command: command))) as? [String: Any])
        data["revision"] = 99
        XCTAssertThrowsError(try ContactPacket.decode(JSONSerialization.data(withJSONObject: data)))
    }
    func testSeparateExportFilesNeverContainPromptOrResponse() async throws {
        let log = EvidenceStore(persist: false)
        log.recordRoom(id: UUID(), date: Date(), elements: 1, origin: .localSensor)
        log.recordGame(mission: UUID(), kind: .contactCommand, action: "inspect:0", revision: 1, score: 100)
        let finished = expectation(description: "export")
        var files: [URL] = []
        log.export { files = $0; finished.fulfill() }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), Set(["observations.json", "telemetry.json", "gameplay.json", "session.json"]))
        let observations = try String(contentsOf: XCTUnwrap(files.first { $0.lastPathComponent == "observations.json" }), encoding: .utf8)
        XCTAssertFalse(observations.contains("inspect:0")); XCTAssertFalse(observations.contains("score"))
        let journal = try EvidenceSnapshot.decode(Data(contentsOf: XCTUnwrap(files.first { $0.lastPathComponent == "session.json" })))
        XCTAssertEqual(journal.observations.count, 1); XCTAssertEqual(journal.gameplay.count, 1)
    }
}
