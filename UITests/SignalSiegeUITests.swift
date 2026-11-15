import XCTest

final class SignalSiegeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openChallenge() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["siege.open"].waitForExistence(timeout: 10))
        app.buttons["siege.open"].tap()
        XCTAssertTrue(app.staticTexts["siege.status"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Signal Siege control is not reachable: \(element.identifier)")
    }

    func testTacticalMovementTurnAndReplayFromTraining() {
        let app = openChallenge()
        XCTAssertTrue(app.staticTexts["siege.status"].label.contains("AP 4/4"))
        XCTAssertFalse(app.buttons["siege.move"].isEnabled)
        app.buttons["siege.cell.1.4"].tap()
        app.buttons["siege.move"].tap()
        XCTAssertTrue(app.staticTexts["siege.status"].label.contains("AP 3/4"))
        app.buttons["siege.endTurn"].tap()
        XCTAssertTrue(app.staticTexts["siege.status"].label.contains("TURN 2"))
        XCTAssertTrue(app.staticTexts["siege.status"].label.contains("AP 4/4"))
        reveal(app.buttons["siege.replay"], in: app)
        app.buttons["siege.replay"].tap()
        app.alerts.buttons["Replay"].tap()
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["siege.status"].label.contains("TURN 1"))
        app.buttons["siege.close"].tap()
        XCTAssertTrue(app.buttons["beginMission"].waitForExistence(timeout: 5))
    }

    func testOfflineNPCAndLocalRankingsClear() {
        let app = openChallenge()
        reveal(app.staticTexts["siege.npc.label"], in: app)
        XCTAssertEqual(app.staticTexts["siege.npc.label"].label, "AI interpretation, fictional NPC")
        XCTAssertEqual(app.staticTexts["siege.npc.source"].label, "Scripted offline dialogue")
        reveal(app.buttons["siege.npc.ask"], in: app)
        XCTAssertFalse(app.buttons["siege.npc.ask"].isEnabled, "No GGUF inference occurs before explicit model loading")
        XCTAssertTrue(app.staticTexts["siege.npc.dialogue"].label.contains("Mica"))
        app.buttons["siege.rankings"].tap()
        XCTAssertTrue(app.staticTexts["siege.rankingsScope"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["siege.noScores"].exists)
        app.buttons["siege.clearRankings"].tap()
        app.buttons["Clear rankings"].tap()
        XCTAssertTrue(app.staticTexts["siege.rankingStatus"].label.contains("cleared"))
        app.buttons["siege.rankingsClose"].tap()
        XCTAssertTrue(app.buttons["siege.close"].exists)
    }
}
