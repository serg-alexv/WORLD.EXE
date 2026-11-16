import Foundation
import XCTest
@testable import EvidenceCore

final class EvidenceCoreTests: XCTestCase {
    let session = UUID()
    let capture = UUID()
    let wall = Date(timeIntervalSince1970: 1_800_000_000)
    func stamp(_ n: UInt64 = 1, uptime: Double? = nil, date: Date? = nil) throws -> EvidenceStamp {
        try EvidenceStamp(session: session, sequence: n, recordedAt: date ?? wall, elapsedSeconds: uptime ?? Double(n))
    }
    func room(_ n: UInt64 = 1) throws -> ObservationRecord {
        try ObservationRecord(stamp: stamp(n), source: .roomPlan, origin: .localSensor, captureID: capture, capturedAt: wall, payload: .roomSummary(elements: 12))
    }
    func game(_ n: UInt64 = 1) throws -> GameEventRecord {
        try GameEventRecord(stamp: stamp(n), missionID: UUID(), kind: .contactCommand, action: "inspect:0", revision: 3, score: 90)
    }
    func telemetry(_ n: UInt64 = 1) throws -> TelemetryRecord { try TelemetryRecord(stamp: stamp(n), payload: .runtime(.nominal)) }
    func corrupt<T: Encodable>(_ record: T, key: String, value: Any) throws -> Data {
        var d = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        d[key] = value; return try JSONSerialization.data(withJSONObject: d)
    }
    func testRoomObservationIsExplicitEstimateNotRawMeasurement() throws {
        let r = try room()
        XCTAssertEqual(r.nature, .estimate); XCTAssertFalse(r.isPhysicalMeasurement)
        XCTAssertEqual(try JSONDecoder().decode(ObservationRecord.self, from: JSONEncoder().encode(r)), r)
        let text = String(decoding: try JSONEncoder().encode(r), as: UTF8.self)
        XCTAssertTrue(text.contains("estimate"))
    }
    func testGameCannotDecodeAsObservationOrTelemetry() throws {
        let data = try JSONEncoder().encode(game())
        XCTAssertThrowsError(try JSONDecoder().decode(ObservationRecord.self, from: data))
        XCTAssertThrowsError(try JSONDecoder().decode(TelemetryRecord.self, from: data))
    }
    func testForgingLaneDoesNotTurnGameIntoSensorData() throws {
        let data = try corrupt(game(), key: "lane", value: "observation")
        XCTAssertThrowsError(try JSONDecoder().decode(ObservationRecord.self, from: data))
    }
    func testObservationCannotClaimCalibratedMeasurement() throws {
        let data = try corrupt(room(), key: "nature", value: "measured")
        XCTAssertThrowsError(try JSONDecoder().decode(ObservationRecord.self, from: data))
    }
    func testModelTextIsNotAnObservationPayload() throws {
        let data = try corrupt(room(), key: "payload", value: ["llmResponse": ["text":"There is radiation"]])
        XCTAssertThrowsError(try JSONDecoder().decode(ObservationRecord.self, from: data))
    }
    func testSourceAndPayloadMustAgree() throws {
        XCTAssertThrowsError(try ObservationRecord(stamp: stamp(), source: .arkit, origin: .localSensor, captureID: capture, payload: .roomSummary(elements: 2)))
        XCTAssertThrowsError(try ObservationRecord(stamp: stamp(), source: .roomPlan, origin: .localSensor, captureID: capture, payload: .tracking(.normal)))
    }
    func testArchivePreservesOriginalTimeAndRequiresProvenance() throws {
        let old = wall.addingTimeInterval(-86_400)
        let r = try ObservationRecord(stamp: stamp(), source: .roomPlan, origin: .restoredArchive, captureID: capture, capturedAt: old, payload: .roomSummary(elements: 5))
        XCTAssertEqual(r.capturedAt, old); XCTAssertNotEqual(r.capturedAt, r.stamp.recordedAt)
        XCTAssertThrowsError(try ObservationRecord(stamp: stamp(), source: .roomPlan, origin: .restoredArchive, captureID: capture, payload: .roomSummary(elements: 5)))
    }
    func testPeerReportRemainsPeerReportAfterSerialization() throws {
        let r = try ObservationRecord(stamp: stamp(), source: .roomPlan, origin: .peerReport, captureID: capture, payload: .roomSummary(elements: 2))
        XCTAssertEqual(try JSONDecoder().decode(ObservationRecord.self, from: JSONEncoder().encode(r)).origin, .peerReport)
    }
    func testNoSyntheticObservationOrigin() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(ObservationRecord.self, from: corrupt(room(), key: "origin", value: "simulation")))
    }
    func testInvalidCountsAndTimestampsAreRejected() throws {
        for count in [0, -1, 513] { XCTAssertThrowsError(try ObservationRecord(stamp: stamp(), source: .roomPlan, origin: .localSensor, captureID: capture, payload: .roomSummary(elements: count))) }
        for t in [-1.0, Double.infinity, Double.nan] { XCTAssertThrowsError(try stamp(uptime: t)) }
        XCTAssertThrowsError(try stamp(0))
    }
    func testBackendRequestIsNotBackendEvidence() throws {
        let s = try InferenceSample(modelSHA256: String(repeating: "a", count: 64), requestedBackend: .metal, tokens: 5, requestSeconds: 2, outcome: .succeeded)
        XCTAssertNil(s.confirmedBackend)
        XCTAssertEqual(s.requestTokensPerSecond, 2.5)
    }
    func testMissingTelemetryStaysUnknownNotZero() throws {
        let s = try InferenceSample(modelSHA256: String(repeating: "a", count: 64), requestedBackend: .cpu, tokens: nil, requestSeconds: nil, outcome: .failed)
        XCTAssertNil(s.tokens); XCTAssertNil(s.requestSeconds); XCTAssertNil(s.requestTokensPerSecond)
    }
    func testZeroDurationDoesNotCreateInfiniteThroughput() throws {
        let s = try InferenceSample(modelSHA256: String(repeating: "a", count: 64), requestedBackend: .metal, tokens: 10, requestSeconds: 0, outcome: .cancelled)
        XCTAssertNil(s.requestTokensPerSecond); XCTAssertEqual(s.outcome, .cancelled)
    }
    func testInvalidModelMetricsRejectedAfterDecoding() throws {
        let s = try InferenceSample(modelSHA256: String(repeating: "a", count: 64), requestedBackend: .cpu, tokens: 10, requestSeconds: 2, outcome: .succeeded)
        let r = try TelemetryRecord(stamp: stamp(), payload: .inference(s))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        var payload = try XCTUnwrap(json["payload"] as? [String: Any]); var inference = try XCTUnwrap(payload["inference"] as? [String: Any]); var sample = try XCTUnwrap(inference["_0"] as? [String: Any])
        sample["tokens"] = -1; inference["_0"] = sample; payload["inference"] = inference; json["payload"] = payload
        XCTAssertThrowsError(try JSONDecoder().decode(TelemetryRecord.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testNetworkMeasurementHasBoundedBytes() throws {
        XCTAssertThrowsError(try TelemetryRecord(stamp: stamp(), payload: .network(bytes: 262145, outbound: false, accepted: true)))
        XCTAssertThrowsError(try TelemetryRecord(stamp: stamp(), payload: .network(bytes: -1, outbound: true, accepted: false)))
    }
    func testSeparateLanesCannotPolluteObservationExport() throws {
        var j = try EvidenceJournal(session: session)
        try j.append(room(1)); try j.append(game(2)); try j.append(telemetry(3))
        XCTAssertEqual(j.snapshot.observations.count, 1); XCTAssertEqual(j.snapshot.gameplay.count, 1); XCTAssertEqual(j.snapshot.telemetry.count, 1)
        let text = String(decoding: try j.snapshot.observationData(), as: UTF8.self)
        XCTAssertFalse(text.contains("gameplay")); XCTAssertFalse(text.contains("score")); XCTAssertFalse(text.contains("inspect:0"))
        XCTAssertFalse(text.contains("telemetry"))
    }
    func testBoundedJournalEvictsOldestOnlyWithinLane() throws {
        var j = try EvidenceJournal(session: session, capacityPerLane: 2)
        try j.append(room(1)); try j.append(game(2)); try j.append(room(3)); try j.append(room(4))
        XCTAssertEqual(j.snapshot.observations.map(\.stamp.sequence), [3,4])
        XCTAssertEqual(j.snapshot.observationEvictions, 1); XCTAssertEqual(j.snapshot.gameplay.count, 1)
    }
    func testRepeatedWraparoundKeepsOrder() throws {
        var j = try EvidenceJournal(session: session, capacityPerLane: 3)
        for n in 1...100 { try j.append(telemetry(UInt64(n))) }
        XCTAssertEqual(j.snapshot.telemetry.map(\.stamp.sequence), [98,99,100])
        XCTAssertEqual(j.snapshot.telemetryEvictions, 97)
    }
    func testClearIsScopedAndPreservesCapacity() throws {
        var j = try EvidenceJournal(session: session, capacityPerLane: 2)
        try j.append(room(1)); try j.append(game(2)); j.clear(.gameplay)
        XCTAssertEqual(j.snapshot.observations.count, 1); XCTAssertTrue(j.snapshot.gameplay.isEmpty)
        try j.append(game(3)); try j.append(game(4)); try j.append(game(5))
        XCTAssertEqual(j.snapshot.gameplay.count, 2); XCTAssertEqual(j.snapshot.gameplayEvictions, 1)
    }
    func testClockChangeDoesNotOrderRecordsByWallTime() throws {
        var j = try EvidenceJournal(session: session)
        try j.append(room(1))
        let t = try TelemetryRecord(stamp: stamp(2, uptime: 2, date: wall.addingTimeInterval(-3600)), payload: .runtime(.fair))
        try j.append(t); XCTAssertEqual(j.lastSequence, 2)
    }
    func testStaleAndForeignRecordsRejectedAtomically() throws {
        var j = try EvidenceJournal(session: session); try j.append(room(2))
        XCTAssertThrowsError(try j.append(game(1))); XCTAssertEqual(j.lastSequence, 2)
        let foreign = try EvidenceStamp(session: UUID(), sequence: 3, recordedAt: wall, elapsedSeconds: 3)
        XCTAssertThrowsError(try j.append(TelemetryRecord(stamp: foreign, payload: .runtime(.nominal))))
        XCTAssertEqual(j.snapshot.telemetry.count, 0)
    }
    func testJournalSnapshotRoundTripAndMalformedVersion() throws {
        var j = try EvidenceJournal(session: session); try j.append(room()); try j.append(game(2))
        let restored = try EvidenceSnapshot.decode(j.snapshot.encoded())
        XCTAssertEqual(restored.observations.count, 1); XCTAssertEqual(restored.gameplay.count, 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: j.snapshot.encoded()) as? [String:Any]); json["schemaVersion"] = 9
        XCTAssertThrowsError(try EvidenceSnapshot.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testInvalidCapacityAndOversizedArchiveRejected() throws {
        for n in [-1,0,1025] { XCTAssertThrowsError(try EvidenceJournal(capacityPerLane: n)) }
        XCTAssertThrowsError(try EvidenceSnapshot.decode(Data(repeating: 32, count: 4 * 1024 * 1024 + 1)))
    }
    func testRelativeClockNeverExposesItsOrigin() throws {
        let clock = try EvidenceClock(monotonicOrigin: 9_876_543)
        XCTAssertEqual(try clock.elapsed(at: 9_876_543), 0)
        XCTAssertEqual(try clock.elapsed(at: 9_876_545.25), 2.25)
        let time = try EvidenceStamp(session: session, sequence: 1, recordedAt: wall, elapsedSeconds: clock.elapsed(at: 9_876_545.25))
        let text = String(decoding: try JSONEncoder().encode(time), as: UTF8.self)
        XCTAssertFalse(text.contains("9876543")); XCTAssertFalse(text.contains("uptime"))
        XCTAssertTrue(text.contains("elapsedSeconds"))
    }
    func testRelativeClockRejectsNonfiniteAndBackwardTime() throws {
        for origin in [-1.0, Double.nan, Double.infinity] { XCTAssertThrowsError(try EvidenceClock(monotonicOrigin: origin)) }
        let clock = try EvidenceClock(monotonicOrigin: 50)
        for next in [49.0, Double.nan, Double.infinity] { XCTAssertThrowsError(try clock.elapsed(at: next)) }
    }
    func testGameFreeTextCannotContainPromptOrNarration() throws {
        XCTAssertThrowsError(try GameEventRecord(stamp: stamp(), missionID: UUID(), kind: .contactCommand, action: "LLM says there is an anomaly"))
    }
}
