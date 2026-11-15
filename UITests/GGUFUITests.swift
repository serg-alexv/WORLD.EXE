import XCTest

final class GGUFUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        if button.isHittable { XCTAssertTrue(button.isEnabled); button.tap(); return }
        for _ in 0..<6 { app.swipeUp(); if button.isHittable { XCTAssertTrue(button.isEnabled); button.tap(); return } }
        for _ in 0..<10 { app.swipeDown(); if button.isHittable { XCTAssertTrue(button.isEnabled); button.tap(); return } }
        XCTFail("Control is not reachable: \(id)")
    }
    func testModelScreenDoesNotPretendToHaveInferenceWithoutAFile() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        tap("openGGUF", in: app)
        XCTAssertTrue(app.staticTexts["ggufBackend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ggufNoModel"].exists)
        XCTAssertFalse(app.buttons["ggufLoad"].isEnabled)
        XCTAssertFalse(app.buttons["ggufGenerate"].isEnabled)
        XCTAssertTrue(app.buttons["ggufImport"].exists)
        XCTAssertTrue(app.buttons["ggufDownload"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "GGUF controls before explicit model installation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testRealGGUFLoadsAnswersAndUnloadsThroughAppControls() {
        // A functional acceptance budget for a cold shared Simulator, not an iPhone latency claim.
        // Integrity verification, actual native generation and unload are still mandatory.
        executionTimeAllowance = 300
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-gguf-ci"]
        app.launch()
        tap("openGGUF", in: app)
        XCTAssertTrue(app.staticTexts["ggufBackend"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ggufNoModel"].exists, "CI must provide the actual pinned GGUF, not a fake model")
        tap("ggufLoad", in: app)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["ggufGenerate"])
        let loadResult = XCTWaiter.wait(for: [loaded], timeout: 180)
        XCTAssertEqual(loadResult, .completed, "Native GGUF loading must succeed. Actual stage: \(app.staticTexts["ggufStatus"].label)")
        XCTAssertTrue(app.staticTexts["ggufBackend"].label.contains("llama.cpp"))
        tap("ggufGenerate", in: app)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Ответ получен на этом устройстве через llama.cpp"), object: app.staticTexts["ggufStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 75), .completed, "No Apple/rules/cloud fallback is accepted")
        XCTAssertTrue(app.staticTexts["ggufResponse"].exists)
        XCTAssertGreaterThan(app.staticTexts["ggufResponse"].label.count, 3)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Real GGUF response through native iOS simulator UI"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tap("ggufUnload", in: app)
        let unloaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["ggufLoad"])
        XCTAssertEqual(XCTWaiter.wait(for: [unloaded], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["ggufGenerate"].isEnabled)
    }
}
