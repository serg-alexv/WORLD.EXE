import XCTest

final class EvidenceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testGameEventsStayOutOfObservationLaneAndClearDoesNotResetGame() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["beginMission"].waitForExistence(timeout: 10))
        app.buttons["beginMission"].tap(); app.buttons["endTurn"].tap()
        app.buttons["evidence.open"].tap()
        XCTAssertTrue(app.staticTexts["evidence.boundary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["evidence.observation.empty"].exists)
        app.segmentedControls["evidence.lanes"].buttons["Игра"].tap()
        XCTAssertFalse(app.staticTexts["evidence.gameplay.count"].label.hasPrefix("Записей: 0"))
        let clear = app.buttons["evidence.clear"]
        for _ in 0..<5 { if clear.isHittable { break }; app.swipeUp() }
        clear.tap()
        let confirmation = app.alerts.firstMatch.buttons["Очистить"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.isHittable)
        confirmation.tap()
        app.buttons["evidence.close"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "TURN 2")).firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Journal clear preserves live mission"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testEmptyTelemetryDoesNotInventPerformanceMeasurements() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["evidence.open"].waitForExistence(timeout: 10)); app.buttons["evidence.open"].tap()
        app.segmentedControls["evidence.lanes"].buttons["Телеметрия"].tap()
        XCTAssertTrue(app.staticTexts["evidence.telemetry.empty"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Telemetry is separate and unknown values are not zero"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
