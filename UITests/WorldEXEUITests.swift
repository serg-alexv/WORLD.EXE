import XCTest

final class WorldEXEUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }
    func testTrainingLaunchAndInstructions() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["trainingLabel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["beginMission"].exists)
        app.buttons["instructions"].tap()
        XCTAssertTrue(app.staticTexts["Expedition field guide"].waitForExistence(timeout: 3))
        app.buttons["closeInstructions"].tap()
        XCTAssertTrue(app.buttons["beginMission"].waitForExistence(timeout: 3))
    }
    func testMissionControlsAndReset() {
        let app = launch()
        app.buttons["beginMission"].tap()
        XCTAssertTrue(app.buttons["endTurn"].isEnabled)
        XCTAssertFalse(app.buttons["confirmMove"].isEnabled)
        XCTAssertFalse(app.buttons["extract"].isEnabled)
        app.buttons["endTurn"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "TURN 2")).firstMatch.exists)
        app.buttons["resetCamera"].tap()
        app.buttons["resetMission"].tap()
        XCTAssertTrue(app.buttons["beginMission"].exists)
        XCTAssertFalse(app.buttons["endTurn"].isEnabled)
    }
    func testCompleteExpeditionThroughRealControls() {
        let app = launch()
        XCTAssertTrue(app.buttons["beginMission"].waitForExistence(timeout: 10))
        app.buttons["beginMission"].tap()
        var captured = false
        for _ in 0..<80 {
            if app.staticTexts["SIGNALS RETURNED"].exists { break }
            if app.buttons["recoverRelic"].isEnabled {
                app.buttons["recoverRelic"].tap()
            } else if app.buttons["extract"].isEnabled {
                app.buttons["extract"].tap()
            } else if app.buttons["confirmMove"].isEnabled {
                if !captured {
                    let screenshot = XCTAttachment(screenshot: app.screenshot())
                    screenshot.name = "Playable isometric sector and plotted route"
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                    captured = true
                }
                app.buttons["confirmMove"].tap()
                let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["endTurn"])
                XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 8), .completed)
            } else if app.buttons["plotObjective"].isEnabled {
                app.buttons["plotObjective"].tap()
            } else {
                XCTAssertTrue(app.buttons["endTurn"].isEnabled)
                app.buttons["endTurn"].tap()
            }
        }
        XCTAssertTrue(app.staticTexts["SIGNALS RETURNED"].exists, "The playable mission must reach extraction, not merely launch.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Three relics recovered and extraction complete"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["beginMission"].tap()
        XCTAssertTrue(app.buttons["endTurn"].isEnabled)
    }
}
