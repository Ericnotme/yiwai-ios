import XCTest

final class YiwaiUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing","-reset-test-data"]
        app.launch()
    }
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot:app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func reveal(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
    func testPracticeReplayTransferAndPersistentNotebook() throws {
        XCTAssertTrue(app.buttons["answerMate"].waitForExistence(timeout:10))
        capture("01-practice")
        app.buttons["answerNotMate"].tap()
        XCTAssertEqual(app.staticTexts["answerResult"].label,"还有一个细节")
        reveal(app.buttons["nextFrame"])
        app.buttons["nextFrame"].tap()
        XCTAssertTrue(app.staticTexts["frameCue"].label.contains("Re8#"))
        capture("02-replay-mate")
        reveal(app.buttons["nextPosition"])
        capture("03-explanation")
        app.buttons["nextPosition"].tap()
        XCTAssertTrue(app.buttons["answerNotMate"].waitForExistence(timeout:5))
        app.buttons["answerNotMate"].tap()
        XCTAssertEqual(app.staticTexts["answerResult"].label,"判断正确")
        reveal(app.buttons["nextFrame"])
        app.buttons["nextFrame"].tap(); app.buttons["nextFrame"].tap()
        XCTAssertTrue(app.staticTexts["frameCue"].label.contains("Kh7"))
        capture("04-changed-position")
        app.tabBars.buttons["错题本"].tap()
        XCTAssertTrue(app.buttons["review-escape-a"].waitForExistence(timeout:5))
        let note = app.textFields["note-escape-a"]
        note.tap(); note.typeText("Check all escapes")
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["错题本"].tap()
        XCTAssertTrue(app.buttons["review-escape-a"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["note-escape-a"].value as? String,"Check all escapes")
        capture("05-notebook-persisted")
        app.buttons["review-escape-a"].tap()
        XCTAssertTrue(app.buttons["answerMate"].waitForExistence(timeout:5))
        app.buttons["answerMate"].tap()
        XCTAssertEqual(app.staticTexts["answerResult"].label,"判断正确")
        app.tabBars.buttons["错题本"].tap()
        XCTAssertTrue(app.staticTexts["0 道待巩固 · 1 道最近答对"].exists)
    }
    func testLessonSelectionAndLicense() throws {
        XCTAssertTrue(app.buttons["chooseLesson"].waitForExistence(timeout:10))
        app.buttons["chooseLesson"].tap()
        app.buttons["lesson-protection"].tap()
        XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["question"].label.contains("Qg7"))
        app.buttons["answerNotMate"].tap()
        XCTAssertEqual(app.staticTexts["answerResult"].label,"判断正确")
        app.tabBars.buttons["关于"].tap()
        let privacy = app.buttons["privacyPolicy"]
        reveal(privacy); privacy.tap()
        XCTAssertTrue(app.navigationBars["隐私政策"].waitForExistence(timeout:5))
        let content = app.staticTexts["privacyPolicyContent"]
        XCTAssertTrue(content.label.contains("不向开发者服务器发送棋谱"))
        capture("release-privacy-policy")
        app.navigationBars.buttons.element(boundBy:0).tap()
        let license = app.buttons["查看 chess.js BSD-2-Clause 许可"]
        reveal(license); license.tap()
        XCTAssertTrue(app.navigationBars["第三方许可"].waitForExistence(timeout:5))
        capture("06-license")
    }
    func testAccessibilityLargestTextFlow() throws {
        XCTAssertTrue(app.buttons["answerMate"].waitForExistence(timeout:10))
        reveal(app.buttons["answerMate"])
        capture("07-largest-text-question")
        XCTAssertTrue(app.buttons["answerMate"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["answerMate"].frame.height,44)
        app.buttons["answerMate"].tap()
        reveal(app.buttons["nextPosition"])
        XCTAssertTrue(app.buttons["nextPosition"].isHittable)
        capture("08-largest-text-explanation")
        app.buttons["nextPosition"].tap()
        reveal(app.buttons["answerNotMate"])
        app.buttons["answerNotMate"].tap()
        XCTAssertEqual(app.staticTexts["answerResult"].label,"判断正确")
    }
    func testColdLaunchWithSimulatedNetworkUnavailable() throws {
        app.terminate()
        app.launchArguments = ["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launch()
        XCTAssertTrue(app.buttons["answerNotMate"].waitForExistence(timeout:10))
        app.buttons["answerNotMate"].tap()
        reveal(app.buttons["nextFrame"])
        app.buttons["nextFrame"].tap()
        XCTAssertTrue(app.staticTexts["frameCue"].label.contains("Re8#"))
        app.terminate()
        app.launchArguments = ["-ui-testing","-simulate-no-network"]
        app.launch()
        app.tabBars.buttons["错题本"].tap()
        XCTAssertTrue(app.buttons["review-escape-a"].waitForExistence(timeout:5))
        capture("10-simulated-offline-relaunch")
    }
    func testPlaybackPausesAcrossBackground() throws {
        XCTAssertTrue(app.buttons["answerMate"].waitForExistence(timeout:10))
        app.buttons["answerMate"].tap()
        reveal(app.buttons["nextPosition"])
        app.buttons["nextPosition"].tap()
        app.buttons["answerNotMate"].tap()
        reveal(app.buttons["playReplay"])
        app.buttons["playReplay"].tap()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for:.runningBackground,timeout:5))
        Thread.sleep(forTimeInterval:4)
        app.activate()
        XCTAssertTrue(app.buttons["playReplay"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["playReplay"].label.contains("播放"))
        let pausedCue = app.staticTexts["frameCue"].label
        Thread.sleep(forTimeInterval:2.2)
        XCTAssertEqual(app.staticTexts["frameCue"].label,pausedCue)
        app.buttons["playReplay"].tap()
        let finished = NSPredicate(format:"label CONTAINS %@","Kh7：")
        expectation(for:finished,evaluatedWith:app.staticTexts["frameCue"])
        waitForExpectations(timeout:6)
        XCTAssertTrue(app.buttons["playReplay"].label.contains("播放"))
        capture("09-background-resumed-replay")
    }
}
