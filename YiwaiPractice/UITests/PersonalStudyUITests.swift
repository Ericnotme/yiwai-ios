import XCTest

final class PersonalStudyUITests:XCTestCase {
    override func setUpWithError()throws{continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait}
    private func launch(reset:Bool=true,large:Bool=false)->XCUIApplication{
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-simulate-no-network"]
        if reset{app.launchArguments.append("-reset-test-data")};if large{app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]}
        app.launch();XCTAssertTrue(app.staticTexts["learningHomeTitle"].waitForExistence(timeout:15));return app
    }
    private func reveal(_ app:XCUIApplication,_ e:XCUIElement){
        for forward in [true,false]{for _ in 0..<14{
            if e.exists && e.isHittable && e.frame.midY>100 && e.frame.midY<app.frame.maxY-100{return}
            app.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:forward ? 0.82:0.20)).press(forDuration:0.05,thenDragTo:app.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:forward ? 0.20:0.82)))
        }};XCTAssertTrue(e.isHittable,app.debugDescription)
    }
    private func tap(_ app:XCUIApplication,_ id:String){let e=app.buttons[id].firstMatch;reveal(app,e);XCTAssertTrue(e.isEnabled,app.debugDescription);e.tap()}
    private func open(_ app:XCUIApplication){tap(app,"openPersonalStudy");XCTAssertTrue(app.navigationBars["个人棋谱实验"].waitForExistence(timeout:10))}
    private func hidden(_ app:XCUIApplication){XCTAssertFalse(app.staticTexts["personalRuleFacts"].exists);XCTAssertFalse(app.staticTexts["personalAnswerSet"].exists);XCTAssertFalse(app.staticTexts["personalHypothesis"].exists);XCTAssertFalse(app.staticTexts["personalFirstResult"].exists)}
    private func none(_ app:XCUIApplication){tap(app,"personalNoMate");tap(app,"personalSubmit")}
    private func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func testLiveDemoFirstAnswersCrashPracticeAndSimulatedTransfer(){
        var app=launch();open(app);tap(app,"personalDemo");hidden(app)
        XCTAssertTrue(app.staticTexts["personalQuestionCount"].waitForExistence(timeout:150),app.debugDescription);hidden(app);shot("personal-01-independent-retrospective")
        none(app);XCTAssertTrue(app.staticTexts["personalQuestionCount"].label.contains("2 / 2"));hidden(app)
        app.terminate();app=launch(reset:false);open(app)
        let link=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","personal-case-")).firstMatch;reveal(app,link);link.tap()
        XCTAssertTrue(app.staticTexts["personalQuestionCount"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["personalQuestionCount"].label.contains("2 / 2"));hidden(app)
        tap(app,"personalNotes");let reason=app.textFields["personalReason"];reveal(app,reason);reason.tap();reason.typeText("synthetic current reason")
        if app.buttons["收起键盘"].exists{app.buttons["收起键盘"].tap()};tap(app,"personalHint");none(app);hidden(app)
        tap(app,"personalFeedback");let hypothesis=app.staticTexts["personalHypothesis"];reveal(app,hypothesis);XCTAssertTrue(hypothesis.exists);shot("personal-02-rule-and-hypothesis")
        let reasonSaved=app.staticTexts["synthetic current reason"];reveal(app,reasonSaved);XCTAssertTrue(reasonSaved.exists)
        tap(app,"personalPractice");XCTAssertTrue(app.staticTexts["personalQuestionCount"].waitForExistence(timeout:15),app.debugDescription);hidden(app);none(app);tap(app,"personalFeedback")
        let due=app.buttons["personalTransfer"];reveal(app,due);XCTAssertFalse(due.isEnabled)
        tap(app,"personalAdvanceDemo");tap(app,"personalTransfer");XCTAssertTrue(app.staticTexts["personalQuestionCount"].waitForExistence(timeout:15),app.debugDescription);hidden(app);shot("personal-03-matched-transfer-simulated-time")
        none(app);hidden(app);none(app);tap(app,"personalFeedback")
        let first=app.staticTexts["personalFirstResult"].firstMatch;reveal(app,first);XCTAssertTrue(first.exists);shot("personal-04-saved-first-answer")
    }
    func testImportIllegalThenNegativeAndExplicitSide(){
        let app=launch();open(app)
        let field=app.textViews["personalPGN"];reveal(app,field);field.tap();field.typeText("1. e5 *")
        if app.buttons["收起键盘"].exists{app.buttons["收起键盘"].tap()}
        let start=app.buttons["personalAnalyze"];reveal(app,start);XCTAssertFalse(start.isEnabled)
        app.segmentedControls["personalSide"].buttons["白方"].tap();tap(app,"personalAnalyze")
        XCTAssertTrue(app.staticTexts["personalImportError"].waitForExistence(timeout:10));shot("personal-illegal-import")
        app.terminate()
        let fresh=launch();open(fresh);let clean=fresh.textViews["personalPGN"];reveal(fresh,clean);clean.tap();clean.typeText("1. e4 e5 2. Nf3 Nc6 *")
        if fresh.buttons["收起键盘"].exists{fresh.buttons["收起键盘"].tap()}
        let side=fresh.segmentedControls["personalSide"].buttons["白方"];reveal(fresh,side);side.tap();tap(fresh,"personalAnalyze")
        XCTAssertTrue(fresh.staticTexts["personalNoPair"].waitForExistence(timeout:30),fresh.debugDescription);XCTAssertFalse(fresh.buttons["personalPractice"].exists);shot("personal-honest-negative")
    }
    func testCapsuleCannotLeakActivePersonalAnswers() {
        let app=launch();open(app);tap(app,"personalDemo")
        XCTAssertTrue(app.staticTexts["personalQuestionCount"].waitForExistence(timeout:150));hidden(app)
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(app.navigationBars["个人棋谱实验"].waitForExistence(timeout:10))
        app.navigationBars.buttons.element(boundBy:0).tap();tap(app,"homeTimeCapsule");tap(app,"exportCapsule")
        XCTAssertTrue(app.alerts["完整导出会暴露对照答案"].waitForExistence(timeout:5))
        app.alerts.buttons["继续保留未完成练习"].tap()
        XCTAssertFalse(app.staticTexts["capsuleResult"].exists)
        app.navigationBars.buttons.element(boundBy:0).tap();open(app)
        let link=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","personal-case-")).firstMatch;reveal(app,link);link.tap()
        XCTAssertTrue(app.staticTexts["personalQuestionCount"].waitForExistence(timeout:10));hidden(app)
    }
    func testLargeTextEarlyEndAndiPadLayout(){
        let app=launch(large:true);open(app);tap(app,"personalDemo")
        XCTAssertTrue(app.staticTexts["personalQuestionCount"].waitForExistence(timeout:150),app.debugDescription);hidden(app)
        let h8=app.buttons["square-h8"];reveal(app,h8);XCTAssertGreaterThan(h8.frame.width,20);XCTAssertLessThanOrEqual(h8.frame.maxX,app.frame.maxX)
        shot("personal-large-layout-before-feedback")
        app.buttons["personalEnd"].tap();app.alerts.buttons["结束并查看"].tap()
        let h=app.staticTexts["personalHypothesis"];reveal(app,h);XCTAssertTrue(h.exists)
        let missing=app.staticTexts["未提交；不计为错误"].firstMatch;reveal(app,missing);XCTAssertTrue(missing.exists);shot("personal-large-layout-feedback")
    }
}
