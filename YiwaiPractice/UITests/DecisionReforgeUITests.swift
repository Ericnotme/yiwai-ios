import XCTest

final class DecisionReforgeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 {
            if element.isHittable { return }
            // Scroll the form margin, outside the editable text views and board gestures.
            app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.75))
                .press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.30)))
        }
        if !element.isHittable {
            capture(app,"reforge-unreachable-control")
            let tree = XCTAttachment(string:app.debugDescription); tree.name = "reforge-ui-tree"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func recordRecollection(_ app: XCUIApplication) {
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launchEnvironment["YIWAI_UI_GAME_MOVES"] = "[\"e2e4\",\"e7e5\"]"
        app.launchEnvironment["YIWAI_UI_CLOCK"] = "2026-10-21T12:00:00Z"
        app.launch(); app.tabBars.buttons["棋谱"].tap()
        app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","record-")).firstMatch.tap()
        app.buttons["captureReviewDecision"].tap()
        XCTAssertEqual(app.staticTexts["decisionOrigin"].label,"事后回忆（可能不完整）")
        let candidates = app.descendants(matching:.any).matching(identifier:"decisionCandidates").firstMatch
        reveal(app,candidates); candidates.tap(); candidates.typeText("Nf3 or Bc4")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        let reason = app.textViews["decisionReason"]
        reveal(app,reason); reason.tap(); reason.typeText("I did not check all replies.")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        let tag = app.descendants(matching:.any).matching(identifier:"decisionTag").firstMatch
        reveal(app,tag); tag.tap(); app.buttons["将军后检查全部合法应将"].tap()
        reveal(app,app.buttons["saveDecision"]); capture(app,"reforge-01-record-recollection")
        app.buttons["saveDecision"].tap()
        XCTAssertTrue(app.buttons["editPersonalNote"].waitForExistence(timeout:5))
        app.terminate()
    }
    private func openItem(_ app: XCUIApplication, time: String = "2026-10-23T12:00:00Z") {
        app.launchArguments = ["-ui-testing","-simulate-no-network"]
        app.launchEnvironment.removeValue(forKey:"YIWAI_UI_GAME_MOVES")
        app.launchEnvironment["YIWAI_UI_CLOCK"] = time
        app.launch(); app.tabBars.buttons["棋谱"].tap(); app.buttons["openDecisionReforge"].tap()
        let item = app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","reforge-item-")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout:5)); item.tap()
        XCTAssertEqual(app.staticTexts["savedDecisionOrigin"].label,"事后回忆（可能不完整）")
    }
    private func start(_ app: XCUIApplication) {
        reveal(app,app.buttons["startReforge"]); app.buttons["startReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeMode"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["reforgeAnswers"].exists)
        XCTAssertFalse(app.staticTexts["reforgeFeedback"].exists)
        XCTAssertFalse(app.staticTexts["reforgeResult"].exists)
    }
    func testIndependentDueReviewPersistsAndTagCanBeCorrected() {
        let app = XCUIApplication(); recordRecollection(app); openItem(app)
        start(app); XCTAssertTrue(app.staticTexts["reforgeMode"].label.contains("到期"))
        app.buttons["square-h5"].tap(); app.buttons["square-h7"].tap()
        reveal(app,app.buttons["submitReforge"])
        XCTAssertEqual(app.staticTexts["reforgePending"].label,"待提交：h5h7")
        capture(app,"reforge-02-before-first-submit")
        app.buttons["submitReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeResult"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["reforgeResult"].label.contains("计入本主题独立通过"))
        XCTAssertTrue(app.staticTexts["reforgeFeedback"].exists)
        capture(app,"reforge-03-independent-feedback")
        app.terminate(); openItem(app)
        reveal(app,app.staticTexts["reforgeMastery"])
        XCTAssertTrue(app.staticTexts["reforgeMastery"].label.contains("已一次独立通过"))
        let tag = app.descendants(matching:.any).matching(identifier:"correctDecisionTag").firstMatch
        for _ in 0..<4 { if tag.isHittable { break }; app.swipeDown() }
        tag.tap(); app.buttons["暂不归类 / 不适用"].tap()
        reveal(app,app.buttons["startReforge"]); app.buttons["startReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeMastery"].label.contains("待准备"))
        capture(app,"reforge-04-honest-waiting")
    }
    func testHintSurvivesRelaunchAndEarlyAttemptDoesNotCount() {
        let app = XCUIApplication(); recordRecollection(app); openItem(app,time:"2026-10-21T14:00:00Z")
        start(app); XCTAssertTrue(app.staticTexts["reforgeMode"].label.contains("提前练习"))
        reveal(app,app.buttons["hintReforge"]); app.buttons["hintReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeHint"].exists)
        XCTAssertFalse(app.staticTexts["reforgeFeedback"].exists)
        app.terminate(); openItem(app,time:"2026-10-21T14:05:00Z")
        start(app)
        reveal(app,app.staticTexts["reforgeHint"])
        XCTAssertTrue(app.staticTexts["reforgeHint"].exists); XCTAssertFalse(app.buttons["hintReforge"].exists)
        for _ in 0..<5 { if app.buttons["square-h5"].isHittable { break }; app.swipeDown() }
        app.buttons["square-h5"].tap(); app.buttons["square-h7"].tap()
        reveal(app,app.buttons["submitReforge"]); app.buttons["submitReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeResult"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["reforgeResult"].label.contains("用过提示"))
        XCTAssertTrue(app.staticTexts["reforgeResult"].label.contains("不计独立掌握"))
        capture(app,"reforge-05-assisted-not-independent")
    }
    func testLiveSkipAndLargestTextQueue() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launch(); app.tabBars.buttons["下棋"].tap(); app.buttons["newGame"].tap(); app.buttons["confirmNewGame"].tap()
        reveal(app,app.buttons["captureLiveDecision"]); app.buttons["captureLiveDecision"].tap()
        XCTAssertEqual(app.staticTexts["decisionOrigin"].label,"落子前记录")
        reveal(app,app.buttons["skipDecision"]); app.buttons["skipDecision"].tap()
        app.tabBars.buttons["棋谱"].tap(); app.buttons["openDecisionReforge"].tap()
        XCTAssertTrue(app.staticTexts["reforgeSkipped"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["reforgeEmpty"].exists)
        capture(app,"reforge-06-live-skip")
        app.terminate()
        app.launchArguments = ["-ui-testing","-simulate-no-network","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); app.tabBars.buttons["棋谱"].tap(); app.buttons["openDecisionReforge"].tap()
        reveal(app,app.staticTexts["reforgeSkipped"])
        capture(app,"reforge-07-largest-text-queue")
    }
}
