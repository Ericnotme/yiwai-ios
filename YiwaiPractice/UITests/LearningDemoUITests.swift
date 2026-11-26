import XCTest

final class LearningDemoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func scroll(_ app:XCUIApplication, up:Bool) {
        // The demo is a full-screen presentation over another scroll view. Use
        // visible app coordinates, away from the board and scroll indicator.
        app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:up ? 0.76 : 0.25))
            .press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:up ? 0.25 : 0.76)))
    }
    private func reveal(_ app:XCUIApplication,_ e:XCUIElement) {
        for _ in 0..<8 { if e.isHittable { return }; scroll(app,up:true) }
        for _ in 0..<12 { if e.isHittable { return }; scroll(app,up:false) }
        XCTAssertTrue(e.isHittable,app.debugDescription)
    }
    private func tap(_ app:XCUIApplication,_ id:String) { let e=app.buttons[id];reveal(app,e);e.tap() }
    private func shot(_ app:XCUIApplication,_ name:String) { let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    private func back(_ app:XCUIApplication) { app.navigationBars.buttons.element(boundBy:0).tap() }
    private func launch(large:Bool=false) -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-reset-test-data","-simulate-no-network"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch();XCTAssertTrue(app.staticTexts["learningHomeTitle"].waitForExistence(timeout:10));return app
    }
    private func scan(_ app:XCUIApplication,_ sample:String) {
        tap(app,"demo-import-\(sample)");tap(app,"demo-check-\(sample)")
        XCTAssertFalse(app.buttons["scanPattern"].isEnabled)
        app.buttons["我执白"].tap();app.buttons["scanPattern"].tap()
        XCTAssertTrue(app.staticTexts["scanSummary"].waitForExistence(timeout:15))
    }
    private func openItem(_ app:XCUIApplication,_ link:String) {
        tap(app,link)
        let item=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","reforge-item-")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout:5));item.tap()
    }
    func testColdStartDemonstrationReasonsPracticeAndDifferentSimulatedRetest() {
        let app=launch();shot(app,"review-01-learning-home")
        tap(app,"startLearningDemo");XCTAssertTrue(app.staticTexts["demoBanner"].waitForExistence(timeout:5))
        scan(app,"queen")
        app.buttons["我执黑"].tap()
        XCTAssertFalse(app.staticTexts["scanSummary"].exists)
        XCTAssertFalse(app.buttons["trainEvidence-0"].exists)
        app.buttons["scanPattern"].tap();XCTAssertTrue(app.staticTexts["noPatternEvidence"].waitForExistence(timeout:10))
        app.buttons["我执白"].tap();app.buttons["scanPattern"].tap()
        XCTAssertTrue(app.staticTexts["patternEvidenceExplanation"].waitForExistence(timeout:10))
        reveal(app,app.staticTexts["patternEvidenceExplanation"]);shot(app,"review-02-rule-evidence")
        tap(app,"trainEvidence-0");tap(app,"addRecollection")
        XCTAssertEqual(app.staticTexts["recollectionTiming"].label,"事后补记 · 已看过反馈")
        let candidates=app.textViews["recollectionCandidates"].exists ? app.textViews["recollectionCandidates"] : app.textFields["recollectionCandidates"]
        candidates.tap();candidates.typeText("Qg5 or Qg7")
        tap(app,"收起键盘")
        let reason=app.textViews["recollectionReason"];reveal(app,reason);reason.tap();reason.typeText("After feedback, I would check every legal reply.")
        tap(app,"收起键盘");shot(app,"review-03-after-feedback-reason");app.buttons["saveRecollection"].tap()
        XCTAssertTrue(app.staticTexts["supplementReason"].waitForExistence(timeout:5))
        tap(app,"startTargetPractice")
        XCTAssertTrue(app.staticTexts["reforgeMode"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["reforgeMode"].label.contains("示例"))
        XCTAssertFalse(app.staticTexts["reforgeAnswers"].exists)
        app.buttons["square-h5"].tap();app.buttons["square-h7"].tap();tap(app,"submitReforge")
        XCTAssertTrue(app.staticTexts["reforgeResult"].label.contains("不计个人进度"));shot(app,"review-04-practice-feedback")
        back(app);back(app);back(app)
        scan(app,"rook")
        XCTAssertTrue(app.staticTexts["gamePatternSummary"].label.contains("重复"));back(app)
        tap(app,"demoDuplicate")
        XCTAssertTrue(app.staticTexts["demoPatternSummary"].label.contains("重复"))
        tap(app,"demoAdvance");XCTAssertTrue(app.staticTexts["demoBanner"].label.contains("已模拟到期"))
        openItem(app,"demoRetest");tap(app,"startReforge")
        XCTAssertTrue(app.staticTexts["reforgeMode"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["reforgeMode"].label.contains("模拟到期"))
        XCTAssertFalse(app.staticTexts["reforgeAnswers"].exists)
        app.buttons["square-h6"].tap();app.buttons["square-f7"].tap();shot(app,"review-05-different-position-before-submit")
        tap(app,"hintReforge");tap(app,"submitReforge")
        XCTAssertTrue(app.staticTexts["reforgeResult"].label.contains("用过提示"));XCTAssertTrue(app.staticTexts["reforgeResult"].label.contains("不计个人进度"))
        shot(app,"review-06-retest-first-answer-and-hint")
        back(app);back(app);back(app)
        app.buttons["closeLearningDemo"].tap()
        reveal(app,app.staticTexts["homeCounts"]);XCTAssertEqual(app.staticTexts["homeCounts"].label,"0 盘本机棋谱 · 0 处个人复习项")
    }
    func testNoEvidenceAndLargestTextHomeRemainOperable() {
        let app=launch(large:true)
        reveal(app,app.buttons["startLearningDemo"]);XCTAssertGreaterThanOrEqual(app.buttons["startLearningDemo"].frame.height,44)
        shot(app,"review-07-largest-text-home");tap(app,"startLearningDemo")
        scan(app,"none")
        XCTAssertTrue(app.staticTexts["noPatternEvidence"].waitForExistence(timeout:10));XCTAssertFalse(app.buttons["trainEvidence-0"].exists)
        reveal(app,app.staticTexts["noPatternEvidence"]);shot(app,"review-08-no-evidence")
        back(app);app.buttons["closeLearningDemo"].tap()
        if app.frame.width > 600 {
            XCUIDevice.shared.orientation = .landscapeLeft
            reveal(app,app.buttons["homeImport"]);XCTAssertTrue(app.buttons["homeImport"].isHittable)
            shot(app,"review-09-ipad-landscape");XCUIDevice.shared.orientation = .portrait
        }
    }
}
