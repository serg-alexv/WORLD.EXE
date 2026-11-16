import XCTest
@testable import WorldCore
final class ArenaTrackingGateTests: XCTestCase {
    func testSyntheticBoardStartsReady() {
        let gate = ArenaTrackingGate()
        XCTAssertTrue(gate.permitsActions(authorityPaused: false))
    }
    func testTrackingLossBlocksResumeAndActions() {
        var gate = ArenaTrackingGate(); gate.updateTracking(false)
        XCTAssertFalse(gate.resume()); XCTAssertTrue(gate.requiresResume)
        XCTAssertFalse(gate.permitsActions(authorityPaused: false))
    }
    func testReacquisitionStillNeedsExplicitResume() {
        var gate = ArenaTrackingGate(); gate.updateTracking(false); gate.updateTracking(true)
        XCTAssertFalse(gate.permitsActions(authorityPaused: false))
        XCTAssertTrue(gate.resume()); XCTAssertTrue(gate.permitsActions(authorityPaused: false))
    }
    func testRepeatedReadyCallbacksCannotClearLatch() {
        var gate = ArenaTrackingGate(); gate.updateTracking(false)
        for _ in 0..<10 { gate.updateTracking(true); XCTAssertFalse(gate.permitsActions(authorityPaused: false)) }
        XCTAssertTrue(gate.requiresResume)
    }
    func testHostPauseAndLocalPauseRemainIndependent() {
        var gate = ArenaTrackingGate(); gate.updateTracking(false); gate.updateTracking(true)
        for authorityPaused in [true, false, true, false] { XCTAssertFalse(gate.permitsActions(authorityPaused: authorityPaused)) }
        XCTAssertTrue(gate.resume()); XCTAssertFalse(gate.permitsActions(authorityPaused: true))
        XCTAssertTrue(gate.permitsActions(authorityPaused: false))
    }
}
