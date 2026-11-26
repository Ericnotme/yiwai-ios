import XCTest

final class TimeCapsuleUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func selectHistoryTab(_ app: XCUIApplication) {
        let phoneTab = app.tabBars.buttons["棋谱"]
        // iPadOS exposes its top-level tabs as ordinary buttons, not a TabBar.
        let tab = phoneTab.exists ? phoneTab : app.buttons.matching(NSPredicate(format: "label == %@", "棋谱")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 8)); tab.tap()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func selectLocalExportDestination(_ app: XCUIApplication) {
        let localRoot = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage,")).firstMatch
        let names = ["On My iPhone", "On My iPad", "我的iPhone", "我的 iPhone", "我的iPad", "我的 iPad"]
        let localLocation = app.cells.matching(NSPredicate(format: "identifier IN %@", names.map { "DOC.sidebar.item." + $0 })).firstMatch
        // A fresh picker may open at Browse rather than remember a destination.
        // Only the explicit on-device sidebar row is eligible for navigation.
        let save = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["保存", "Save"])).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in localLocation.isHittable || (localRoot.exists && save.exists) }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, app.debugDescription)
        // Browse can retain a stale localRoot wrapper after navigating back.
        // A visible local sidebar row must still be selected explicitly.
        if localLocation.isHittable {
            capture(app, "export-browse-before-local-selection")
            localLocation.tap()
        }
        // A sidebar row/title/filename is not proof of the selected provider.
        XCTAssertTrue(localRoot.waitForExistence(timeout: 20), app.debugDescription)
    }
    private func reveal(_ app: XCUIApplication, _ item: XCUIElement) {
        for _ in 0..<8 { if item.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(item.isHittable)
    }
    func testOfflineImportNoteRelaunchAndExportPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launch(); selectHistoryTab(app)
        app.buttons["importPosition"].tap(); app.buttons["PGN 棋谱"].tap()
        let input = app.textViews["importText"]
        input.tap(); input.typeText("1. e4 {Local original comment} (1. d4 d5) e5 2. Nf3 Nc6 *")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        reveal(app,app.buttons["confirmImport"])
        app.buttons["confirmImport"].tap()
        XCTAssertTrue(app.buttons["editPersonalNote"].waitForExistence(timeout:10))
        app.buttons["editPersonalNote"].tap()
        let note = app.textViews["personalNoteInput"]
        XCTAssertTrue(note.waitForExistence(timeout:5)); note.tap(); note.typeText("Look for the opponent's threat.\nA local memory.")
        capture(app,"capsule-01-personal-note")
        app.buttons["savePersonalNote"].tap()
        XCTAssertTrue(app.buttons["editPersonalNote"].waitForExistence(timeout:5))
        app.terminate(); app.launchArguments = ["-ui-testing","-simulate-no-network"]; app.launch()
        selectHistoryTab(app)
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
        selectLocalExportDestination(app)
        XCTAssertFalse(app.staticTexts["capsuleError"].exists)
        capture(app,"capsule-03-system-file-export")
        if filename.exists {
            filename.tap(); filename.typeText("-UITest-"+String(UUID().uuidString.prefix(8)))
        }
        let save = app.navigationBars.buttons.matching(
            NSPredicate(format: "label IN %@", ["保存", "Save"])
        ).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout:5))
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:save)],timeout:20),.completed,app.debugDescription)
        save.tap()
        XCTAssertTrue(app.staticTexts["capsuleResult"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["capsuleResult"].label.contains("已导出"))
        capture(app,"capsule-06-export-saved")
        app.terminate()
    }
    func testLargestTextCapsuleAndNoteControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["YIWAI_UI_GAME_MOVES"] = "[\"e2e4\",\"e7e5\"]"
        app.launch(); selectHistoryTab(app)
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
