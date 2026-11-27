import XCTest

final class FortressLabUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testDirectChallengePromotionUndoAndRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-test-data", "-simulate-no-network"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 8))
            for _ in 0..<5 {
                if element.isHittable { break }
                let status = app.staticTexts["fortressStatus"]
                if status.exists && status.isHittable {
                    // Start outside the playable board: dragging on the board
                    // is a chess move, not a request to scroll the page.
                    status.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        .press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
                } else { app.swipeUp() }
            }
            XCTAssertTrue(element.isHittable, app.debugDescription)
            element.tap()
        }
        tap(app.buttons["fortressEntry"])
        tap(app.buttons["fortressChallengeEntry"])
        XCTAssertTrue(app.staticTexts["fortressStatus"].waitForExistence(timeout: 8))
        let status = app.staticTexts["fortressStatus"]
        for piece in ["后", "车", "象", "马"] {
            app.swipeDown()
            tap(app.buttons["square-a7"])
            tap(app.buttons["square-a8"])
            tap(app.buttons[piece])
            XCTAssertTrue(status.waitForExistence(timeout: 8))
            XCTAssertTrue(status.label.contains("和棋"))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "fortress-promotion-\(piece)"; shot.lifetime = .keepAlways; add(shot)
            tap(app.buttons["fortressUndo"])
            XCTAssertTrue(status.label.contains("轮到白方"))
        }
        tap(app.buttons["fortressChangeSeed"])
        XCTAssertTrue(app.staticTexts["从第二横线开始"].exists)
        tap(app.buttons["fortressRestart"])
        XCTAssertTrue(status.label.contains("轮到白方"))
        XCTAssertFalse(app.staticTexts["fortressError"].exists)
        let restarted = XCTAttachment(screenshot: app.screenshot())
        restarted.name = "fortress-second-challenge-restarted"; restarted.lifetime = .keepAlways; add(restarted)
    }
    func testCourseAnswerEvidenceRelaunchAndRetryPreservesFirstAnswer() throws {
        let app=XCUIApplication()
        app.launchArguments=["-ui-testing","-reset-test-data","-simulate-no-network"]
        app.launch()
        func tap(_ element:XCUIElement, inTrailingSpace:Bool = false) {
            XCTAssertTrue(element.waitForExistence(timeout:10))
            for _ in 0..<7 {
                if element.isHittable && element.frame.midY > 110 && element.frame.midY < app.frame.maxY-90 { break }
                app.swipeUp()
            }
            XCTAssertTrue(element.isHittable)
            if inTrailingSpace {
                // The complete row must respond, including space beside its text.
                element.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)).tap()
            } else { element.tap() }
        }
        tap(app.buttons["fortressEntry"])
        XCTAssertTrue(app.staticTexts["fortressCourseProgress"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["fortressCourseProgress"].label,"已作答 0 / 16 题")
        tap(app.buttons["fortressChapter-geometry"],inTrailingSpace:true)
        tap(app.buttons["fortressQuestion-geometry-wrong-color"],inTrailingSpace:true)
        tap(app.buttons["fortressNo"])
        XCTAssertTrue(app.staticTexts["fortressQuizFeedback"].label.contains("再看一处细节"))
        XCTAssertTrue(app.staticTexts["fortressSavedAnswer"].label.contains("首答：不合法"))
        app.swipeDown()
        tap(app.buttons["走之后"])
        XCTAssertTrue(app.staticTexts["fortressEvidencePosition"].label.contains("走后"))
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="fortress-course-answer-and-evidence";shot.lifetime = .keepAlways;add(shot)
        app.terminate();app.launchArguments=["-ui-testing","-simulate-no-network"];app.launch()
        tap(app.buttons["fortressEntry"])
        XCTAssertTrue(app.staticTexts["fortressCourseProgress"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["fortressCourseProgress"].label,"已作答 1 / 16 题")
        tap(app.buttons["fortressChapter-geometry"],inTrailingSpace:true)
        tap(app.buttons["fortressQuestion-geometry-wrong-color"],inTrailingSpace:true)
        tap(app.buttons["fortressRedo"])
        tap(app.buttons["fortressYes"])
        XCTAssertTrue(app.staticTexts["fortressSavedAnswer"].label.contains("首答：不合法；最近：合法；已作答 2 次"))
        XCTAssertFalse(app.staticTexts["fortressError"].exists)
        XCTAssertFalse(app.staticTexts["fortressSaveError"].exists)
    }

}
