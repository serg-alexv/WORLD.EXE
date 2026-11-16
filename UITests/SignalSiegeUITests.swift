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
        let dialog = app.alerts.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        dialog.buttons["Start fresh session"].firstMatch.tap()
        for _ in 0..<7 { if app.staticTexts["siege.status"].isHittable { break }; app.swipeDown() }
        XCTAssertTrue(app.staticTexts["siege.status"].label.contains("TURN 1"))
        app.buttons["siege.close"].tap()
        XCTAssertTrue(app.buttons["beginMission"].waitForExistence(timeout: 5))
    }

    func testOfflineNPCAndLocalRankingsClear() {
        let app = openChallenge()
        reveal(app.staticTexts["siege.npc.label"], in: app)
        XCTAssertEqual(app.staticTexts["siege.npc.label"].label, "ВЫМЫШЛЕННЫЙ NPC · НЕ НАБЛЮДЕНИЕ")
        XCTAssertEqual(app.staticTexts["siege.npc.source"].label, "Сценарная реплика · без генерации")
        reveal(app.buttons["siege.npc.ask"], in: app)
        XCTAssertFalse(app.buttons["siege.npc.ask"].isEnabled, "No GGUF inference occurs before explicit model loading")
        XCTAssertTrue(app.staticTexts["siege.npc.dialogue"].label.contains("КИРА"))
        app.buttons["siege.rankings"].tap()
        XCTAssertTrue(app.staticTexts["siege.rankingsScope"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["siege.noScores"].exists)
        app.buttons["siege.clearRankings"].tap()
        let confirm = app.buttons["siege.confirmClear"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()
        // The store updates synchronously; the accessibility projection can lag the sheet animation.
        // Wait for the SAME postcondition; never replace it with a weaker no-scores assertion.
        let status = app.staticTexts["siege.rankingStatus"]
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", "cleared"), object: status)
        let result = XCTWaiter.wait(for: [cleared], timeout: 5)
        if result != .completed {
            let diagnostics = XCTAttachment(string: "rankingStatus=\(status.exists ? status.label : "MISSING")\n" + app.debugDescription)
            diagnostics.name = "Ranking-clear failure accessibility state"; diagnostics.lifetime = .keepAlways; add(diagnostics)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Ranking-clear failure screen"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
        XCTAssertEqual(result, .completed, "Clear confirmation did not publish success: \(status.exists ? status.label : "MISSING")")
        XCTAssertTrue(app.staticTexts["siege.noScores"].exists)
        app.buttons["siege.rankingsClose"].tap()
        XCTAssertTrue(app.buttons["siege.close"].exists)
    }
    func testHumorSelectorChangesCopyWithoutChangingMission() {
        let app = openChallenge()
        let before = app.staticTexts["siege.status"].label
        let picker = app.segmentedControls["siege.humor"]
        reveal(picker, in: app)
        picker.buttons["Чёрный"].tap()
        let dialogue = app.staticTexts["siege.npc.dialogue"]
        reveal(dialogue, in: app)
        XCTAssertTrue(dialogue.label.contains("Эвакуируем бюджет"))
        picker.buttons["Без шуток"].tap()
        XCTAssertTrue(dialogue.label.contains("Заберите сигнал"))
        picker.buttons["Сарказм"].tap()
        XCTAssertTrue(dialogue.label.contains("План нам пока не выдали"))
        XCTAssertEqual(app.staticTexts["siege.status"].label, before)
        XCTAssertEqual(app.staticTexts["siege.npc.source"].label, "Сценарная реплика · без генерации")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Signal Siege tone selector and explicitly scripted NPC"
        shot.lifetime = .keepAlways; add(shot)
    }

}
