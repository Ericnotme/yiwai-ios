import XCTest

final class TimeCapsuleUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func reveal(_ app: XCUIApplication, _ item: XCUIElement) {
        for _ in 0..<8 { if item.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(item.isHittable)
    }
    func testOfflineImportNoteRelaunchAndExportPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launch(); app.tabBars.buttons["棋谱"].tap()
        app.buttons["importPosition"].tap(); app.buttons["PGN 棋谱"].tap()
        let input = app.textViews["importText"]
        input.tap(); input.typeText("1. e4 {Local original comment} (1. d4 d5) e5 2. Nf3 Nc6 *")
        app.buttons["confirmImport"].tap()
        XCTAssertTrue(app.buttons["editPersonalNote"].waitForExistence(timeout:10))
        app.buttons["editPersonalNote"].tap()
        let note = app.textViews["personalNoteInput"]
        XCTAssertTrue(note.waitForExistence(timeout:5)); note.tap(); note.typeText("Look for the opponent's threat.\nA local memory.")
        capture(app,"capsule-01-personal-note")
        app.buttons["savePersonalNote"].tap()
        XCTAssertTrue(app.buttons["editPersonalNote"].waitForExistence(timeout:5))
        app.terminate(); app.launchArguments = ["-ui-testing","-simulate-no-network"]; app.launch()
        app.tabBars.buttons["棋谱"].tap()
        let record = app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","record-")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout:5)); record.tap()
        app.buttons["editPersonalNote"].tap()
        XCTAssertEqual(app.textViews["personalNoteInput"].value as? String,"Look for the opponent's threat.\nA local memory.")
        app.buttons["取消"].tap()
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["openTimeCapsule"].tap()
        XCTAssertTrue(app.staticTexts["capsuleCounts"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["capsuleCounts"].label.contains("1 盘"))
        capture(app,"capsule-02-overview")
        reveal(app,app.buttons["exportCapsule"]); app.buttons["exportCapsule"].tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout:15),app.debugDescription)
        // Save synthetic test data only, and only when the local device destination is visible.
        XCTAssertTrue(app.navigationBars.staticTexts["我的iPhone"].exists)
        XCTAssertFalse(app.staticTexts["capsuleError"].exists)
        capture(app,"capsule-03-system-file-export")
        filename.tap(); filename.typeText("-UITest-"+String(UUID().uuidString.prefix(8)))
        app.navigationBars.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["capsuleResult"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["capsuleResult"].label.contains("已导出"))
        capture(app,"capsule-06-export-saved")
        app.terminate()
    }
    func testLargestTextCapsuleAndNoteControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["YIWAI_UI_GAME_MOVES"] = "[\"e2e4\",\"e7e5\"]"
        app.launch(); app.tabBars.buttons["棋谱"].tap()
        let record = app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","record-")).firstMatch
        reveal(app,record); record.tap()
        reveal(app,app.buttons["editPersonalNote"]); app.buttons["editPersonalNote"].tap()
        XCTAssertTrue(app.textViews["personalNoteInput"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["savePersonalNote"].isHittable)
        capture(app,"capsule-04-largest-text-note")
        app.buttons["取消"].tap(); app.navigationBars.buttons.element(boundBy:0).tap()
        for _ in 0..<5 { if app.buttons["openTimeCapsule"].isHittable { break }; app.swipeDown() }
        app.buttons["openTimeCapsule"].tap()
        reveal(app,app.buttons["exportCapsule"])
        XCTAssertGreaterThanOrEqual(app.buttons["exportCapsule"].frame.height,44)
        capture(app,"capsule-05-largest-text-export")
    }
}
