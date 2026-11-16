import XCTest

final class ContactUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false; app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-fusion-ui-testing", "-contact-hot-seat"]
        app.launch()
        XCTAssertTrue(app.buttons["fusion.game"].waitForExistence(timeout: 12))
        app.buttons["fusion.game"].tap()
    }
    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id]
        if button.waitForExistence(timeout: 3) && button.isHittable { XCTAssertTrue(button.isEnabled, file: file, line: line); button.tap(); return }
        for _ in 0..<5 { app.swipeUp(); if button.exists && button.isHittable { XCTAssertTrue(button.isEnabled, file: file, line: line); button.tap(); return } }
        for _ in 0..<8 { app.swipeDown(); if button.exists && button.isHittable { XCTAssertTrue(button.isEnabled, file: file, line: line); button.tap(); return } }
        XCTFail("Control unavailable: \(id)", file: file, line: line)
    }
    func testHotSeatCompletesThroughRealControls() throws {
        // Navigate through the actual Fusion launcher, then complete every CONTACT action.
        tap("contact.open"); tap("contact.demo")
        XCTAssertTrue(app.staticTexts["contact.demo.banner"].exists)
        for n in 0..<3 {
            tap("contact.role.researcher"); tap("contact.node.\(n)"); tap("contact.inspect")
            let glyph = app.staticTexts["contact.glyph.\(n)"]
            XCTAssertTrue(glyph.waitForExistence(timeout: 2))
            let channels = ["Круг": 2, "Треугольник": 0, "Ромб": 1]
            let channel = try XCTUnwrap(channels[glyph.label], "Researcher must inspect a real glyph")
            tap("contact.role.operator"); tap("contact.node.\(n)"); tap("contact.power"); tap("contact.channel.\(channel)")
            tap("contact.role.researcher"); tap("contact.stabilize")
        }
        tap("contact.role.operator"); tap("contact.arm")
        tap("contact.role.researcher"); tap("contact.capsule"); tap("contact.extract")
        XCTAssertTrue(app.staticTexts["contact.success"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["contact.demo.banner"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "CONTACT cooperative role-switch mission completed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tap("contact.replay")
        XCTAssertFalse(app.staticTexts["contact.success"].exists)
        tap("contact.node.0"); tap("contact.inspect")
        XCTAssertTrue(app.staticTexts["contact.glyph.0"].waitForExistence(timeout: 2))
    }
}
