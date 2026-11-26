import XCTest

final class ConditionStudyUITests:XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false;XCUIDevice.shared.orientation = .portrait }
    private func reveal(_ app:XCUIApplication,_ element:XCUIElement) {
        for direction in [true,false] {
            for _ in 0..<9 {
                let footer=app.buttons["pauseConditionStudy"]
                let visibleBottom=footer.exists ? footer.frame.minY-8 : app.frame.maxY-115
                let visible=element.exists && (footer.exists ? element.frame.minY > 110 && element.frame.maxY < visibleBottom : element.frame.midY > 110 && element.frame.midY < visibleBottom)
                if element.exists && element.isHittable && (["pauseConditionStudy","endConditionStudy","收起键盘"].contains(element.identifier) || element.label=="收起键盘" || visible) { return }
                // Keep content controls above the actual fixed footer, which
                // becomes taller at accessibility text sizes. Use the content
                // rather than the transparent outer margin for scrolling.
                let lower=footer.exists ? min(0.80,(footer.frame.minY-app.frame.minY-40)/app.frame.height) : 0.80
                let x:CGFloat=footer.exists ? 0.50 : 0.97
                app.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:x,dy:direction ? lower:0.20))
                    .press(forDuration:0.05,thenDragTo:app.windows.firstMatch.coordinate(withNormalizedOffset:CGVector(dx:x,dy:direction ? 0.20:lower)))
            }
        }
        XCTAssertTrue(element.isHittable,app.debugDescription)
    }
    private func tap(_ app:XCUIApplication,_ id:String) {
        let b=app.buttons[id].firstMatch;reveal(app,b)
        if !b.exists { XCTAssertTrue(b.waitForExistence(timeout:5)) }
        if !b.isEnabled { XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:b)],timeout:15) == .completed,app.debugDescription) }
        b.tap()
    }
    private func shot(_ name:String) { let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
    private func waitForExportState(_ app: XCUIApplication, _ stage: String, timeout: TimeInterval = 60, condition: @escaping () -> Bool) -> Bool {
        let error = app.staticTexts["capsuleError"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in error.exists || condition() }, object: app)
        let status = XCTWaiter.wait(for: [ready], timeout: timeout)
        guard status == .completed && !error.exists else {
            shot("export-" + stage + "-failed")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "export-" + stage + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            XCTFail(error.exists ? "Export failed: \(error.label)" : "Export did not reach \(stage) within \(timeout)s (\(status))")
            return false
        }
        return true
    }
    private func prepareUniqueExportDirectory(_ app: XCUIApplication) -> Bool {
        let folderName = "Yiwai-Conditions-UITest-" + UUID().uuidString
        let rootPrefix = "DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage, Title: "
        let more = app.buttons["OverflowBarButtonItem"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        captureState(app, "folder-save-01-menu")
        let newFolder = app.buttons.matching(NSPredicate(format:"label IN %@", ["新建文件夹", "New Folder"])).firstMatch
        XCTAssertTrue(newFolder.waitForExistence(timeout: 10)); XCTAssertTrue(newFolder.isEnabled); newFolder.tap()
        captureState(app, "folder-save-02-before-name")
        let naming = app.textViews["DOC.inlineRenameField"]
        XCTAssertTrue(naming.waitForExistence(timeout: 10))
        naming.typeText(folderName)
        XCTAssertEqual(naming.value as? String, folderName)
        captureState(app, "folder-save-03-named")
        // Commit through the focused naming editor; keyboard Done can leave it editing.
        naming.typeText("\n")
        guard waitForExportState(app, "directory-name-committed", timeout: 10, condition: { !naming.exists }) else { return false }
        captureState(app, "folder-save-04-after-return")
        let exactRoot = rootPrefix + folderName
        let selected = app.otherElements.matching(NSPredicate(format: "identifier == %@", exactRoot)).firstMatch
        let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        let title = navigation.staticTexts.matching(NSPredicate(format: "label == %@", folderName)).firstMatch
        let titleMenu = navigation.buttons.matching(NSPredicate(format: "identifier != %@ AND label BEGINSWITH %@", "BackButton", folderName + ", ")).firstMatch
        let isSelected = {
            selected.exists && selected.identifier == exactRoot &&
                (title.exists || (titleMenu.exists && titleMenu.label.components(separatedBy: ", ").first == folderName))
        }
        let directory = app.cells.matching(NSPredicate(format: "identifier == %@", folderName + ", Folder")).firstMatch
        guard waitForExportState(app, "uuid-directory-ready", timeout: 20, condition: {
            isSelected() || (directory.exists && directory.isHittable)
        }) else { return false }
        if !isSelected() {
            XCTAssertEqual(directory.identifier, folderName + ", Folder")
            directory.tap()
        }
        guard waitForExportState(app, "uuid-directory-selected", timeout: 20, condition: isSelected) else { return false }
        XCTAssertEqual(selected.identifier, exactRoot)
        XCTAssertTrue(isSelected())
        captureState(app, "folder-save-05-selected-directory")
        return true
    }
    private func captureState(_ app: XCUIApplication, _ name: String) {
        let tree = XCTAttachment(string:app.debugDescription); tree.name=name+"-hierarchy"; tree.lifetime = .keepAlways; add(tree)
        let screen = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); screen.name=name; screen.lifetime = .keepAlways; add(screen)
    }
    private func verifyExportCompleted(_ app: XCUIApplication) -> Bool {
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        guard waitForExportState(app, "picker-dismissed", condition: { !picker.exists }) else { return false }
        let result = app.staticTexts["capsuleResult"]
        for _ in 0..<8 {
            if app.staticTexts["capsuleError"].exists || (result.exists && result.isHittable) { break }
            app.swipeUp()
        }
        return waitForExportState(app, "success-visible", timeout: 10, condition: {
            result.exists && result.isHittable && result.label.contains("已导出")
        })
    }
    private func selectLocalExportDestination(_ app: XCUIApplication) -> Bool {
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        // Picker accessibility readiness is separate from selecting its provider.
        guard waitForExportState(app, "picker-present", condition: { picker.exists }) else { return false }
        let localRoot = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage,")).firstMatch
        let names = ["On My iPhone", "On My iPad", "我的iPhone", "我的 iPhone", "我的iPad", "我的 iPad"]
        let localLocation = app.cells.matching(NSPredicate(format: "identifier IN %@", names.map { "DOC.sidebar.item." + $0 })).firstMatch
        // A fresh picker may open at Browse rather than remember a destination.
        // Only the explicit on-device sidebar row is eligible for navigation.
        let save = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["保存", "Save"])).firstMatch
        guard waitForExportState(app, "local-location-ready", timeout: 20, condition: {
            (localLocation.exists && localLocation.isHittable) || (localRoot.exists && save.exists)
        }) else { return false }
        // Browse can retain a stale localRoot wrapper after navigating back.
        // A visible local sidebar row must still be selected explicitly.
        if localLocation.exists && localLocation.isHittable {
            shot("export-browse-before-local-selection")
            localLocation.tap()
        }
        // A sidebar row/title/filename is not proof of the selected provider.
        return waitForExportState(app, "local-root-selected", timeout: 20, condition: { localRoot.exists })
    }
    private func launch(reset:Bool=true,large:Bool=false,clock:String="2026-10-24T01:00:00Z") -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-simulate-no-network"]
        if reset { app.launchArguments.append("-reset-test-data") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["YIWAI_UI_CLOCK"]=clock;app.launch();XCTAssertTrue(app.staticTexts["learningHomeTitle"].waitForExistence(timeout:10));return app
    }
    private func open(_ app:XCUIApplication) { tap(app,"openConditionStudy");XCTAssertTrue(app.navigationBars["条件对照 · 实验"].waitForExistence(timeout:10),app.debugDescription) }
    private func checkHidden(_ app:XCUIApplication) {
        XCTAssertFalse(app.staticTexts["conditionSummary"].exists);XCTAssertFalse(app.staticTexts["conditionVerifiedAnswers"].exists)
        XCTAssertFalse(app.staticTexts["conditionFirstAnswer"].exists);XCTAssertFalse(app.staticTexts["conditionCompletion"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","完整一步杀答案")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","指定吃子机会：")).firstMatch.exists)
    }
    private func answerNone(_ app:XCUIApplication) { tap(app,"conditionNoMate");tap(app,"submitConditionAnswer") }
    func testFirstAnswersPauseCrashUnifiedFeedbackAndDelayedTransfer() {
        var app=launch();open(app);tap(app,"startConditionStudy")
        XCTAssertTrue(app.staticTexts["conditionProgress"].waitForExistence(timeout:10),app.debugDescription);checkHidden(app)
        shot("conditions-01-independent-position")
        answerNone(app)
        XCTAssertTrue(app.staticTexts["conditionProgress"].label.contains("2 / 12"));checkHidden(app)
        tap(app,"pauseConditionStudy");app.terminate()
        app=launch(reset:false);open(app);tap(app,"resumeConditionStudy");tap(app,"resumeConditionTrial")
        XCTAssertTrue(app.staticTexts["conditionProgress"].label.contains("2 / 12"));checkHidden(app)
        for i in 2...12 {
            XCTAssertTrue(app.staticTexts["conditionProgress"].label.contains("\(i) / 12"));checkHidden(app);answerNone(app)
        }
        XCTAssertTrue(app.staticTexts["conditionSummary"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["conditionCompletion"].label.contains("12/12"));shot("conditions-02-complete-feedback")
        app.navigationBars.buttons.element(boundBy:0).tap();XCTAssertTrue(app.navigationBars["条件对照 · 实验"].waitForExistence(timeout:5),app.debugDescription);tap(app,"startConditionTransfer")
        reveal(app,app.staticTexts["conditionHomeError"]);XCTAssertTrue(app.staticTexts["conditionHomeError"].label.contains("24 小时"))
        app.terminate();app=launch(reset:false,clock:"2026-10-25T01:00:00Z");open(app);tap(app,"startConditionTransfer")
        XCTAssertTrue(app.staticTexts["conditionProgress"].waitForExistence(timeout:10),app.debugDescription);checkHidden(app)
        XCTAssertTrue(app.staticTexts["conditionProgress"].label.contains("1 / 4"));shot("conditions-03-transfer-injected-24h")
        for _ in 0..<4 { answerNone(app) }
        XCTAssertTrue(app.staticTexts["conditionCompletion"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["conditionCompletion"].label.contains("4/4"))
        shot("conditions-04-transfer-feedback")
    }
    func testOptionalNotesHintMarkerEarlyEndAndExportDoesNotLeak() {
        let app=launch();open(app);tap(app,"startConditionStudy")
        XCTAssertTrue(app.staticTexts["conditionProgress"].waitForExistence(timeout:10),app.debugDescription)
        tap(app,"conditionOptionalNotes")
        let hierarchy=XCTAttachment(string:app.debugDescription);hierarchy.name="condition-optional-accessibility";hierarchy.lifetime = .keepAlways;add(hierarchy)
        let field=app.descendants(matching:.any).matching(identifier:"conditionCandidates").firstMatch
        reveal(app,field);field.tap();field.typeText("Check all replies")
        tap(app,"收起键盘");tap(app,"conditionAssisted");checkHidden(app)
        tap(app,"pauseConditionStudy");app.navigationBars.buttons.element(boundBy:0).tap()
        tap(app,"homeTimeCapsule");tap(app,"exportCapsule")
        XCTAssertTrue(app.alerts["完整导出会暴露对照答案"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textFields["DOCPicker.filenameTextField"].exists)
        app.alerts.buttons["继续保留未完成练习"].tap();app.navigationBars.buttons.element(boundBy:0).tap()
        open(app);tap(app,"resumeConditionStudy");tap(app,"resumeConditionTrial")
        checkHidden(app);answerNone(app);tap(app,"endConditionStudy");app.alerts.buttons["结束并查看"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["conditionCompletion"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["conditionCompletion"].label.contains("1/12"))
        XCTAssertTrue(app.staticTexts["conditionMissing"].firstMatch.exists)
        let notes=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Check all replies")).firstMatch
        reveal(app,notes);XCTAssertTrue(notes.exists);shot("conditions-05-optional-report-and-exclusion")
        tap(app,"查看局面、证明与单独重试")
        XCTAssertTrue(app.staticTexts["conditionVerifiedAnswers"].waitForExistence(timeout:5))
        tap(app,"conditionRetry");tap(app,"没有一步将死");tap(app,"saveConditionRetry")
        XCTAssertTrue(app.staticTexts["conditionVerifiedAnswers"].waitForExistence(timeout:5));shot("conditions-06-rule-evidence")
    }
    func testExplicitCompleteExportEndsRoundWithoutInventingAnswers() {
        let app=launch();open(app);tap(app,"startConditionStudy")
        XCTAssertTrue(app.staticTexts["conditionProgress"].waitForExistence(timeout:10))
        tap(app,"pauseConditionStudy");app.navigationBars.buttons.element(boundBy:0).tap()
        tap(app,"homeTimeCapsule");tap(app,"exportCapsule")
        XCTAssertTrue(app.alerts["完整导出会暴露对照答案"].waitForExistence(timeout:5))
        app.alerts.buttons["结束对照并导出"].firstMatch.tap()
        guard selectLocalExportDestination(app) else { return }
        XCTAssertFalse(app.staticTexts["capsuleError"].exists);shot("conditions-09-explicit-complete-export")
        guard prepareUniqueExportDirectory(app) else { return }
        XCTAssertTrue(app.otherElements.matching(NSPredicate(format:"identifier BEGINSWITH %@","DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage,")).firstMatch.exists,app.debugDescription)
        let save=app.navigationBars.buttons.matching(NSPredicate(format:"label IN %@",["保存","Save"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout:5))
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:save)],timeout:20),.completed,app.debugDescription)
        save.tap()
        guard verifyExportCompleted(app) else { return }
        shot("conditions-10-export-saved")
        app.navigationBars.buttons.element(boundBy:0).tap();open(app)
        let result=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","0/12 项已提交")).firstMatch
        reveal(app,result);result.tap()
        XCTAssertTrue(app.staticTexts["conditionCompletion"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["conditionCompletion"].label.contains("0/12"))
        XCTAssertTrue(app.staticTexts["conditionMissing"].firstMatch.exists)
    }
    func testLargestTextDemoAndTabletLandscape() {
        let app=launch(large:true);open(app);tap(app,"startConditionDemo")
        XCTAssertTrue(app.staticTexts["conditionProgress"].waitForExistence(timeout:10),app.debugDescription);XCTAssertTrue(app.staticTexts["conditionProgress"].label.contains("演示"));checkHidden(app)
        reveal(app,app.buttons["conditionNoMate"]);XCTAssertGreaterThanOrEqual(app.buttons["conditionNoMate"].frame.height,44)
        XCTAssertLessThan(app.buttons["conditionNoMate"].frame.maxY,app.buttons["pauseConditionStudy"].frame.minY)
        tap(app,"conditionNoMate")
        XCTAssertTrue(app.staticTexts["conditionPending"].label.contains("待提交：没有一步将死"))
        shot("conditions-07-largest-text")
        reveal(app,app.buttons["submitConditionAnswer"])
        XCTAssertLessThan(app.buttons["submitConditionAnswer"].frame.maxY,app.buttons["pauseConditionStudy"].frame.minY)
        tap(app,"submitConditionAnswer")
        XCTAssertTrue(app.staticTexts["conditionProgress"].label.contains("2 / 12"))
        if app.frame.width>600 { XCUIDevice.shared.orientation = .landscapeLeft;reveal(app,app.buttons["conditionNoMate"]);shot("conditions-08-ipad-landscape");XCUIDevice.shared.orientation = .portrait }
        tap(app,"endConditionStudy");app.alerts.buttons["结束并查看"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["统一反馈"].waitForExistence(timeout:10),app.debugDescription)
        reveal(app,app.staticTexts["conditionCompletion"])
        XCTAssertTrue(app.staticTexts["conditionCompletion"].label.contains("本轮为演示"))
    }
}
