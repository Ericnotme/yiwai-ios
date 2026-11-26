import XCTest

final class FortressLabUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testPredictionPromotionUndoAndRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-test-data", "-simulate-no-network"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 8))
            for _ in 0..<5 {
                if element.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(element.isHittable)
            element.tap()
        }
        tap(app.buttons["fortressEntry"])
        tap(app.buttons["fortressYes"])
        tap(app.buttons["fortressNext"])
        tap(app.buttons["fortressNo"])
        tap(app.buttons["fortressNext"])
        tap(app.buttons["fortressYes"])
        tap(app.buttons["fortressNext"])
        XCTAssertTrue(app.staticTexts["fortressStatus"].waitForExistence(timeout: 8))
        let status = app.staticTexts["fortressStatus"]
        for piece in ["后", "车", "象", "马"] {
            app.swipeDown()
            tap(app.buttons["square-a7"])
            tap(app.buttons["square-a8"])
            tap(app.buttons[piece])
            XCTAssertTrue(status.waitForExistence(timeout: 8))
            XCTAssertTrue(status.label.contains("和棋"))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "fortress-promotion-\(piece)"; shot.lifetime = .keepAlways; add(shot)
            tap(app.buttons["fortressUndo"])
            XCTAssertTrue(status.label.contains("轮到白方"))
        }
        tap(app.buttons["fortressChangeSeed"])
        tap(app.buttons["fortressRestart"])
        XCTAssertTrue(status.label.contains("轮到白方"))
        XCTAssertFalse(app.staticTexts["fortressError"].exists)
    }
}
