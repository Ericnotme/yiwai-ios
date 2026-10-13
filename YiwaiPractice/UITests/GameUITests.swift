import XCTest

final class GameUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false; app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launch(); app.tabBars.buttons["下棋"].tap()
    }
    func newGame() {
        app.buttons["newGame"].tap()
        XCTAssertTrue(app.buttons["confirmNewGame"].waitForExistence(timeout:5))
        app.buttons["confirmNewGame"].tap()
        XCTAssertTrue(app.buttons["square-e2"].waitForExistence(timeout:5))
    }
    func reveal(_ item: XCUIElement) { for _ in 0..<6 { if item.isHittable { return }; app.swipeUp() } }
    func capture(_ name: String) { let a = XCTAttachment(screenshot:app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testOfflineGameReplyReviewEvidenceAndPersistence() {
        newGame(); capture("game-01-board")
        app.buttons["square-e2"].tap(); app.buttons["square-e4"].tap()
        let replied = NSPredicate(format:"label == %@","2 半回合")
        expectation(for:replied,evaluatedWith:app.staticTexts["plyCount"]); waitForExpectations(timeout:12)
        capture("game-02-ai-reply")
        reveal(app.buttons["reviewGame"]); app.buttons["reviewGame"].tap()
        XCTAssertTrue(app.buttons["reviewNext"].waitForExistence(timeout:8)); app.buttons["reviewNext"].tap()
        reveal(app.buttons["analyzeGame"]); app.buttons["analyzeGame"].tap()
        XCTAssertTrue(app.staticTexts["coachTitle"].waitForExistence(timeout:20))
        XCTAssertTrue(app.otherElements["accuracyCard"].exists || app.staticTexts["整局准确度"].exists || app.staticTexts["当前棋谱准确度 · 棋局未结束"].exists)
        reveal(app.buttons["bestEvidence"]); capture("game-03-coach")
        app.buttons["bestEvidence"].tap()
        XCTAssertTrue(app.buttons["evidenceNext"].waitForExistence(timeout:5)); app.buttons["evidenceNext"].tap()
        XCTAssertTrue(app.staticTexts["evidencePly"].label.hasPrefix("1 /")); capture("game-04-evidence")
        app.terminate(); app.launchArguments = ["-ui-testing","-simulate-no-network"]; app.launch()
        app.tabBars.buttons["下棋"].tap()
        XCTAssertEqual(app.staticTexts["plyCount"].label,"2 半回合")
        XCTAssertTrue(app.staticTexts["gameStatus"].label.contains("保存") || app.staticTexts["gameStatus"].label.contains("暂停"))
        app.tabBars.buttons["棋谱"].tap(); capture("game-05-persisted-history")
    }
    func testDragMoveAndCancelledReview() {
        newGame()
        let source = app.buttons["square-e2"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        let destination = app.buttons["square-e4"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        source.press(forDuration:0.3,thenDragTo:destination)
        expectation(for:NSPredicate(format:"label == %@","2 半回合"),evaluatedWith:app.staticTexts["plyCount"]); waitForExpectations(timeout:12)
        reveal(app.buttons["reviewGame"]); app.buttons["reviewGame"].tap()
        XCTAssertTrue(app.buttons["reviewNext"].waitForExistence(timeout:8)); app.buttons["reviewNext"].tap()
        reveal(app.buttons["analyzeGame"]); app.buttons["细致"].tap(); app.buttons["analyzeGame"].tap()
        XCTAssertTrue(app.buttons["cancelAnalysis"].waitForExistence(timeout:3)); app.buttons["cancelAnalysis"].tap()
        XCTAssertFalse(app.staticTexts["coachTitle"].exists)
        XCTAssertEqual(app.staticTexts["analysisProgress"].label,"已分析 0 / 2 步")
        capture("game-13-cancel-no-score")
    }
    func testPauseUndoAndNewGameDoNotReceiveStaleMoves() {
        newGame(); app.buttons["square-e2"].tap(); app.buttons["square-e4"].tap()
        reveal(app.buttons["pauseGame"]); app.buttons["pauseGame"].tap()
        let stopped = app.staticTexts["plyCount"].label
        Thread.sleep(forTimeInterval:2.2); XCTAssertEqual(app.staticTexts["plyCount"].label,stopped)
        app.buttons["undoGame"].tap(); XCTAssertEqual(app.staticTexts["plyCount"].label,"0 半回合")
        app.swipeDown(); app.buttons["newGame"].tap(); app.buttons["confirmNewGame"].tap()
        Thread.sleep(forTimeInterval:2.2); XCTAssertEqual(app.staticTexts["plyCount"].label,"0 半回合")
    }
    func testBackgroundPausesComputerAndInput() {
        newGame(); app.buttons["square-e2"].tap(); app.buttons["square-e4"].tap()
        XCUIDevice.shared.press(.home); XCTAssertTrue(app.wait(for:.runningBackground,timeout:5))
        Thread.sleep(forTimeInterval:2); app.activate()
        XCTAssertTrue(app.staticTexts["gameStatus"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["gameStatus"].label.contains("暂停"))
        capture("game-06-background-paused")
    }
    func testPromotionPickerAndTerminalResult() {
        app.terminate(); app.launchArguments = ["-ui-testing","-reset-test-data","-ui-promotion-fixture"]; app.launch()
        app.tabBars.buttons["下棋"].tap()
        app.buttons["square-a7"].tap(); app.buttons["square-a8"].tap()
        XCTAssertTrue(app.buttons["升马"].waitForExistence(timeout:5)); capture("game-07-promotion-choices")
        app.buttons["升马"].tap()
        capture("game-08-after-promotion")
        let finished = NSPredicate(format:"label CONTAINS %@", "1/2-1/2")
        expectation(for:finished,evaluatedWith:app.staticTexts["gameStatus"]); waitForExpectations(timeout:3)
        XCTAssertTrue(app.staticTexts["gameStatus"].label.contains("子力不足")); capture("game-08-terminal-result")
    }
    func testBlackOrientationAndFirstComputerMove() {
        app.buttons["newGame"].tap(); app.buttons["黑方后行"].tap(); app.buttons["confirmNewGame"].tap()
        let replied = NSPredicate(format:"label == %@","1 半回合")
        expectation(for:replied,evaluatedWith:app.staticTexts["plyCount"]); waitForExpectations(timeout:12)
        XCTAssertGreaterThan(app.buttons["square-h8"].frame.minY,app.buttons["square-h1"].frame.minY)
        XCTAssertLessThan(app.buttons["square-h8"].frame.minX,app.buttons["square-a8"].frame.minX)
        capture("game-09-black-board")
    }
    func testLargestTextGameAndReview() {
        newGame(); capture("game-10-largest-text-board")
        app.buttons["square-e2"].tap(); app.buttons["square-e4"].tap()
        expectation(for:NSPredicate(format:"label == %@","2 半回合"),evaluatedWith:app.staticTexts["plyCount"])
        waitForExpectations(timeout:12)
        reveal(app.buttons["reviewGame"]); app.buttons["reviewGame"].tap()
        XCTAssertTrue(app.buttons["reviewNext"].waitForExistence(timeout:8))
        reveal(app.buttons["reviewNext"]); app.buttons["reviewNext"].tap()
        reveal(app.buttons["analyzeGame"]); app.buttons["analyzeGame"].tap()
        XCTAssertTrue(app.staticTexts["coachTitle"].waitForExistence(timeout:20))
        let accuracy = app.descendants(matching:.any).matching(identifier:"whiteAccuracy").firstMatch
        for _ in 0..<8 { if accuracy.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(accuracy.isHittable)
        capture("game-14-largest-accuracy")
        reveal(app.buttons["bestEvidence"])
        XCTAssertGreaterThanOrEqual(app.buttons["bestEvidence"].frame.height,44)
        XCTAssertGreaterThanOrEqual(app.buttons["bestEvidence"].frame.minX,0)
        XCTAssertLessThanOrEqual(app.buttons["bestEvidence"].frame.maxX,app.frame.width)
        capture("game-11-largest-text-coach")
        app.buttons["bestEvidence"].tap()
        XCTAssertTrue(app.buttons["evidenceNext"].waitForExistence(timeout:5))
        reveal(app.buttons["evidenceNext"]); app.buttons["evidenceNext"].tap()
        XCTAssertTrue(app.staticTexts["evidencePly"].label.hasPrefix("1 /"))
        capture("game-12-largest-text-evidence")
    }
}
