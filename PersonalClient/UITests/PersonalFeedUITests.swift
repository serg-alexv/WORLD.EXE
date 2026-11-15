import XCTest

final class PersonalFeedUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["-feed-ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["feed.demo"].waitForExistence(timeout: 10)); return app
    }
    func testDemoProvenanceNoteAndLock() {
        let app = launch(); app.buttons["feed.demo"].tap()
        XCTAssertTrue(app.staticTexts["feed.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["feed.mode"].label.contains("ВЫМЫШЛЕННЫЕ"))
        app.buttons["feed.item.demo-01"].tap()
        let note = app.textFields["feed.note"]
        for _ in 0..<4 { if note.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap(); note.typeText("Synthetic local note")
        let save = app.buttons["feed.saveNote"]
        for _ in 0..<3 { if save.isHittable { break }; app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["Synthetic local note"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Synthetic source and separate personal note"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["feed.lock"].tap()
        XCTAssertTrue(app.buttons["feed.demo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic local note"].exists)
    }
    func testDemoDeletionDoesNotPretendRemoteAccountDeletion() {
        let app = launch(); app.buttons["feed.demo"].tap()
        app.tabBars.buttons["Источники"].tap()
        XCTAssertFalse(app.buttons["feed.addSource"].isEnabled)
        app.buttons["feed.source.demonstration"].tap()
        app.buttons["feed.deleteSource"].tap()
        app.buttons["Удалить источник"].tap()
        app.tabBars.buttons["Лента"].tap()
        XCTAssertTrue(app.staticTexts["feed.count"].label.contains("0"))
    }
    func testPersonalSourceSetupHasNoInventedLiveHornetLogin() {
        let app = launch(); app.buttons["feed.unlock"].tap()
        XCTAssertTrue(app.tabBars.buttons["Источники"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Источники"].tap(); app.buttons["feed.addSource"].tap()
        let label = app.textFields["feed.sourceLabel"]; XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap(); label.typeText("Synthetic Hornet source")
        app.buttons["feed.createSource"].tap()
        XCTAssertTrue(app.buttons["feed.source.hornet"].waitForExistence(timeout: 5))
        app.buttons["feed.source.hornet"].tap()
        XCTAssertTrue(app.buttons["feed.import"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["feed.sourceCount"].label.contains("0"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Hornet manual import capability, no live authentication"; shot.lifetime = .keepAlways; add(shot)
    }
}
