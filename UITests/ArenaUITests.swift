import XCTest
final class ArenaUITests:XCTestCase {
    func testSyntheticArenaControlsAndExit() {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-fusion-ui-testing"];app.launch()
        XCTAssertTrue(app.staticTexts["fusion.title"].waitForExistence(timeout:12))
        let open=app.buttons["fusion.arena"];for _ in 0..<4 {if open.isHittable {break};app.swipeUp()};open.tap()
        XCTAssertTrue(app.buttons["arena.start"].waitForExistence(timeout:8));app.buttons["arena.start"].tap()
        XCTAssertTrue(app.staticTexts["arena.status"].waitForExistence(timeout:5))
        app.buttons["arena.fire"].tap();app.buttons["arena.target"].tap()
        app.buttons["arena.pause"].tap();XCTAssertFalse(app.buttons["arena.fire"].isEnabled)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Arena actual synthetic 3D board";shot.lifetime = .keepAlways;add(shot)
        app.buttons["arena.close"].tap();XCTAssertTrue(app.staticTexts["fusion.title"].waitForExistence(timeout:5))
    }
}
