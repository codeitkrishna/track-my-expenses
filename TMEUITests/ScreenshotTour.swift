import XCTest

/// Walks every screen with sample data and attaches a screenshot of each.
/// Skipped unless run with TEST_RUNNER_TME_SCREENSHOTS=1 set for xcodebuild.
@MainActor
final class ScreenshotTour: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TME_SCREENSHOTS"] != nil, "Screenshot tour not requested")
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    func testTour() {
        let sms = "Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 17/10/26\nRef 629012345678\nNot You?"
        app.launchArguments = ["-uiTesting", "-seedDemo", "-simulateSMS", Data(sms.utf8).base64EncodedString()]
        app.launch()
        XCTAssertTrue(app.staticTexts["Needs a category"].waitForExistence(timeout: 5))
        shot("01-activity")

        app.buttons["setBalanceButton"].tap()
        let balanceField = app.textFields["balanceField"]
        XCTAssertTrue(balanceField.waitForExistence(timeout: 5))
        balanceField.typeText("52340")
        shot("01b-balance-editor")
        app.buttons["saveBalanceButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["balanceValue"].firstMatch.waitForExistence(timeout: 5))
        shot("01c-activity-with-balance")
        app.swipeUp()
        shot("02-activity-scrolled")
        app.swipeDown()

        app.buttons["addButton"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("349")
        app.buttons["pick-Food"].tap()
        shot("03-quick-add")
        app.buttons["Cancel"].tap()

        let row = app.descendants(matching: .any)["entry-Swiggy"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        sleep(1)
        shot("04-edit-entry")
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Where it went"].waitForExistence(timeout: 5))
        shot("05-dashboard")
        app.swipeUp()
        sleep(1)
        shot("06-dashboard-scrolled")
        // Tap the tallest bar area in the day-by-day chart.
        let chartTitle = app.staticTexts["Day by day"]
        if chartTitle.exists {
            chartTitle.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 180, dy: 200)).tap()
            sleep(1)
            shot("07-dashboard-day-selected")
        }

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shot("08-settings")
        app.buttons["Prompt history"].tap()
        sleep(1)
        shot("08b-prompt-history")
        back()

        app.buttons["Categories"].tap()
        sleep(1)
        shot("09-categories")
        app.staticTexts["Food"].firstMatch.tap()
        sleep(1)
        shot("10-category-editor")
        app.buttons["Cancel"].tap()
        back()

        app.buttons["Auto-log bank SMS"].tap()
        sleep(1)
        shot("11-sms-setup")
        back()

        app.buttons["Test a bank SMS"].tap()
        let field = app.textFields["smsTesterField"].exists ? app.textFields["smsTesterField"] : app.textViews["smsTesterField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("ICICI Bank Acct XX123 debited for Rs 250.00 on 17-Oct-26; SWIGGY credited. UPI:629012345678.")
        sleep(1)
        shot("12-sms-tester")
        back()

        app.buttons["Floating quick-add button"].tap()
        sleep(1)
        shot("13-floating-button")
    }
}
