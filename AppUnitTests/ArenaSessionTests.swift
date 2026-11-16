import XCTest
@testable import WorldEXE
@MainActor final class ArenaSessionTests: XCTestCase {
    func testTrackingRestorationDoesNotResumeSoloImplicitly() {
        let session = ArenaSession(); defer { session.stop() }
        session.beginSolo(); XCTAssertTrue(session.canAct)
        session.setTracking(false); XCTAssertFalse(session.canAct); XCTAssertTrue(session.needsTrackingResume)
        session.togglePause(); XCTAssertFalse(session.canAct)
        session.setTracking(true); XCTAssertFalse(session.canAct)
        session.togglePause(); XCTAssertTrue(session.canAct); XCTAssertFalse(session.needsTrackingResume)
    }
    func testFreshSyntheticSessionResetsOnlyItsOwnTrackingLatch() {
        let session = ArenaSession(); defer { session.stop() }
        session.beginSolo(); session.setTracking(false); session.stop()
        XCTAssertFalse(session.active); session.beginSolo()
        XCTAssertTrue(session.canAct); XCTAssertFalse(session.needsTrackingResume)
    }
}
