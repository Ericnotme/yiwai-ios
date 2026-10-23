import XCTest
final class LearningPatternUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    private func reveal(_ app:XCUIApplication,_ target:XCUIElement) {
        for _ in 0..<12 {
            if target.isHittable { return }
            app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.76)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.25)))
        }
        XCTAssertTrue(target.isHittable,app.debugDescription)
    }
    private func shot(_ app:XCUIApplication,_ name:String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    private func importGame(_ app:XCUIApplication,_ pgn:String) {
        app.tabBars.buttons["棋谱"].tap();app.buttons["importPosition"].tap();app.buttons["PGN 棋谱"].tap()
        let input=app.textViews["importText"];input.tap();input.typeText(pgn)
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        reveal(app,app.buttons["confirmImport"]);app.buttons["confirmImport"].tap()
        XCTAssertTrue(app.buttons["editPersonalNote"].waitForExistence(timeout:10))
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.buttons["openLearningPattern"].waitForExistence(timeout:5))
    }
    private func openPattern(_ app:XCUIApplication) {
        app.buttons["openLearningPattern"].tap()
        app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","pattern-game-")).firstMatch.tap()
        XCTAssertFalse(app.buttons["scanPattern"].isEnabled)
        app.buttons["我执白"].tap();app.buttons["scanPattern"].tap()
        XCTAssertTrue(app.staticTexts["scanSummary"].waitForExistence(timeout:20))
    }
    func testPGNToEvidencePracticeThenNewDueReviewAndPersistence() {
        let app=XCUIApplication()
        app.launchArguments=["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launchEnvironment["YIWAI_UI_CLOCK"]="2026-10-23T12:00:00Z"
        app.launch()
        importGame(app,"[Event \"Synthetic learning loop\"]\n[SetUp \"1\"]\n[FEN \"7k/8/5KQ1/8/8/8/8/8 w - - 0 1\"]\n\n1. Qg5 *")
        openPattern(app)
        XCTAssertTrue(app.staticTexts["scanSummary"].label.contains("1 步未采用"))
        XCTAssertTrue(app.staticTexts["gamePatternSummary"].label.contains("不足"))
        reveal(app,app.staticTexts["patternEvidenceExplanation"]);shot(app,"loop-01-pgn-rule-evidence")
        reveal(app,app.buttons["trainEvidence-0"]);app.buttons["trainEvidence-0"].tap()
        reveal(app,app.buttons["startTargetPractice"]);app.buttons["startTargetPractice"].tap()
        XCTAssertTrue(app.staticTexts["reforgeMode"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["reforgeMode"].label.contains("针对性练习"))
        XCTAssertFalse(app.staticTexts["reforgeFeedback"].exists)
        app.buttons["square-h5"].tap();app.buttons["square-h7"].tap()
        reveal(app,app.buttons["submitReforge"]);app.buttons["submitReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeResult"].label.contains("不计到期独立复测"));shot(app,"loop-02-practice-result")
        app.terminate();app.launchArguments=["-ui-testing","-simulate-no-network"]
        app.launchEnvironment["YIWAI_UI_CLOCK"]="2026-10-25T12:00:00Z";app.launch()
        app.tabBars.buttons["棋谱"].tap();app.buttons["openDecisionReforge"].tap()
        app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","reforge-item-")).firstMatch.tap()
        XCTAssertEqual(app.staticTexts["savedDecisionOrigin"].label,"棋谱规则证据（非用户理由）")
        reveal(app,app.buttons["startReforge"]);app.buttons["startReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeMode"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["reforgeMode"].label.contains("到期复习"))
        XCTAssertFalse(app.staticTexts["reforgeFeedback"].exists)
        app.buttons["square-h6"].tap();app.buttons["square-f7"].tap()
        reveal(app,app.buttons["submitReforge"]);shot(app,"loop-03-different-due-position")
        app.buttons["submitReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeResult"].label.contains("计入本主题独立通过"));shot(app,"loop-04-first-independent-result")
    }
    func testNoSupportedEvidenceDoesNotInventTraining() {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-reset-test-data","-simulate-no-network"];app.launch()
        // Public actual game: Fischer–Spassky, Reykjavik 1972, round 6.
        // Source: https://www.pgnmentor.com/events/WorldChamp1972.pgn
        importGame(app,"""
[Event "World Championship 28th"]
[Site "Reykjavik"]
[Date "1972.??.??"]
[Round "6"]
[White "Fischer, Robert James"]
[Black "Spassky, Boris V"]
[Result "1-0"]
[WhiteElo "2785"]
[BlackElo "2660"]
[ECO "D59"]

1.c4 e6 2.Nf3 d5 3.d4 Nf6 4.Nc3 Be7 5.Bg5 O-O 6.e3 h6 7.Bh4 b6 8.cxd5 Nxd5
9.Bxe7 Qxe7 10.Nxd5 exd5 11.Rc1 Be6 12.Qa4 c5 13.Qa3 Rc8 14.Bb5 a6 15.dxc5 bxc5
16.O-O Ra7 17.Be2 Nd7 18.Nd4 Qf8 19.Nxe6 fxe6 20.e4 d4 21.f4 Qe7 22.e5 Rb8
23.Bc4 Kh8 24.Qh3 Nf8 25.b3 a5 26.f5 exf5 27.Rxf5 Nh7 28.Rcf1 Qd8 29.Qg3 Re7
30.h4 Rbb7 31.e6 Rbc7 32.Qe5 Qe8 33.a4 Qd8 34.R1f2 Qe8 35.R2f3 Qd8 36.Bd3 Qe8
37.Qe4 Nf6 38.Rxf6 gxf6 39.Rxf6 Kg8 40.Bc4 Kh8 41.Qf4  1-0
""");openPattern(app)
        XCTAssertTrue(app.staticTexts["scanSummary"].label.contains("41 步"))
        XCTAssertTrue(app.staticTexts["noPatternEvidence"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["trainEvidence-0"].exists)
        shot(app,"loop-05-no-evidence")
    }
    func testKeyboardTextEntryAndCorrection() {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-reset-test-data","-simulate-no-network"];app.launch()
        app.tabBars.buttons["棋谱"].tap();app.buttons["importPosition"].tap()
        let input=app.textViews["importText"];input.tap();input.typeText("1234")
        input.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:4))
        XCTAssertEqual(input.value as? String, "")
        input.typeText("7k/8/5KQ1/8/8/8/8/8 w - - 0 1")
        XCTAssertEqual(input.value as? String,"7k/8/5KQ1/8/8/8/8/8 w - - 0 1")
        app.buttons["收起键盘"].tap();XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["importToolbar"].tap()
        XCTAssertTrue(app.staticTexts["positionTurn"].waitForExistence(timeout:10))
        shot(app,"loop-06-keyboard-import")
    }

}
