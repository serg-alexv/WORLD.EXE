import XCTest

/// These tests deliberately use the real hub instead of the legacy test-navigation route.
final class FusionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-fusion-ui-testing", "-feed-ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["fusion.title"].waitForExistence(timeout: 12))
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    func testHubOpensRealGameAndReturnsWithoutResettingNavigation() {
        let app = launch()
        app.buttons["fusion.game"].tap()
        XCTAssertTrue(app.buttons["siege.open"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["contact.open"].exists)
        XCTAssertTrue(app.buttons["openGGUF"].exists)
        app.buttons["siege.open"].tap()
        XCTAssertTrue(app.staticTexts["siege.status"].waitForExistence(timeout: 5))
        app.buttons["siege.close"].tap()
        app.buttons["fusion.home"].tap()
        XCTAssertTrue(app.staticTexts["fusion.title"].waitForExistence(timeout: 8))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Fusion hub actual app"
        shot.lifetime = .keepAlways; add(shot)
    }
    func testFeedLocksOnWorkspaceExitAndNeverStartsInference() {
        let app = launch()
        reveal(app.buttons["fusion.feed"], app: app); app.buttons["fusion.feed"].tap()
        XCTAssertTrue(app.buttons["feed.demo"].waitForExistence(timeout: 6))
        app.buttons["feed.demo"].tap()
        XCTAssertTrue(app.staticTexts["feed.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["feed.mode"].label.contains("ВЫМЫШЛЕННЫЕ"))
        XCTAssertFalse(app.buttons["openGGUF"].exists)
        XCTAssertFalse(app.buttons["siege.open"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Fusion personal feed synthetic data only"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["fusion.feedClose"].tap()
        XCTAssertTrue(app.staticTexts["fusion.title"].waitForExistence(timeout: 6))
        reveal(app.buttons["fusion.feed"], app: app); app.buttons["fusion.feed"].tap()
        XCTAssertTrue(app.buttons["feed.unlock"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["feed.demo"].exists)
        XCTAssertFalse(app.staticTexts["feed.mode"].exists, "Reopening must not retain an unlocked session")
    }
    func testPrivateSourcePersistsAcrossCloseAndGameSwitch() {
        let app = launch()
        reveal(app.buttons["fusion.feed"], app: app); app.buttons["fusion.feed"].tap()
        app.buttons["feed.unlock"].tap()
        XCTAssertTrue(app.tabBars.buttons["Источники"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Источники"].tap(); app.buttons["feed.addSource"].tap()
        let label = app.textFields["feed.sourceLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 5)); label.tap(); label.typeText("FUSION SYNTHETIC SOURCE")
        app.buttons["feed.createSource"].tap()
        let source = app.buttons["feed.source.hornet"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 6))
        app.buttons["fusion.feedClose"].tap()
        XCTAssertTrue(app.staticTexts["fusion.title"].waitForExistence(timeout: 5))
        app.buttons["fusion.game"].tap()
        XCTAssertTrue(app.buttons["siege.open"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["FUSION SYNTHETIC SOURCE"].exists)
        app.buttons["fusion.home"].tap()
        reveal(app.buttons["fusion.feed"], app: app); app.buttons["fusion.feed"].tap()
        app.buttons["feed.unlock"].tap()
        XCTAssertTrue(app.tabBars.buttons["Источники"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Источники"].tap()
        XCTAssertTrue(app.buttons["feed.source.hornet"].firstMatch.waitForExistence(timeout: 5))
    }
}
