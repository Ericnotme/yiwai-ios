import XCTest

final class PositionImportUITests: XCTestCase {
    func testFENErrorImportAnalyzeAndPGNFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launch()
        app.tabBars.buttons["棋谱"].tap()
        app.buttons["importPosition"].tap()
        let input = app.textViews["importText"]
        XCTAssertTrue(input.waitForExistence(timeout:5))
        input.tap(); input.typeText("invalid")
        app.buttons["importToolbar"].tap()
        XCTAssertTrue(app.staticTexts["importError"].waitForExistence(timeout:5))
        input.tap()
        // Replace the rejected input using keyboard editing.
        input.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:7))
        XCTAssertEqual(input.value as? String, "")
        input.typeText("7k/8/5KQ1/8/8/8/8/8 w - - 0 1")
        app.buttons["importToolbar"].tap()
        XCTAssertTrue(app.staticTexts["positionTurn"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["positionTurn"].label.hasPrefix("白"))
        for _ in 0..<4 { if app.buttons["analyzeGame"].isHittable { break }; app.swipeUp() }
        app.buttons["analyzeGame"].tap()
        XCTAssertTrue(app.staticTexts["positionScore"].waitForExistence(timeout:30))
        XCTAssertFalse(app.staticTexts["whiteAccuracy"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "FEN iPhone analysis"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["positionEvidence"].tap()
        XCTAssertTrue(app.buttons["evidenceNext"].waitForExistence(timeout:5))
        app.buttons["evidenceNext"].tap()
        XCTAssertTrue(app.staticTexts["evidencePly"].label.hasPrefix("1 /"))
        app.terminate()
        app.launchArguments = ["-ui-testing","-simulate-no-network"]
        app.launch(); app.tabBars.buttons["棋谱"].tap()
        XCTAssertTrue(app.staticTexts["FEN · 独立局面"].waitForExistence(timeout:5))
        app.buttons["importPosition"].tap()
        app.buttons["PGN 棋谱"].tap()
        app.textViews["importText"].tap(); app.textViews["importText"].typeText("1. e4 e5 2. Nf3 Nc6 *")
        app.buttons["importToolbar"].tap()
        XCTAssertTrue(app.buttons["reviewNext"].waitForExistence(timeout:10))
        app.buttons["reviewNext"].tap()
        XCTAssertTrue(app.staticTexts["reviewPly"].label.hasPrefix("1 / 4"))
    }
}
