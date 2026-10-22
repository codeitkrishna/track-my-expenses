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
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Also straight to disk when asked (TEST_RUNNER_TME_SHOTS_DIR), so the
        // pictures don't depend on xcodebuild finishing its result bundle.
        if let directory = ProcessInfo.processInfo.environment["TME_SHOTS_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The back button: whichever button sits furthest left in the bar.
    private func back() {
        let buttons = app.navigationBars.firstMatch.buttons.allElementsBoundByIndex
        buttons.min { $0.frame.minX < $1.frame.minX }?.tap()
    }

    /// Just the add menu, held open.
    func testAddMenu() {
        app.launchArguments = ["-uiTesting", "-seedDemo"]
        app.launch()
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 5))
        app.buttons["addButton"].press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 5))
        sleep(1)
        shot("06-add-options")
    }

    /// Splitting a payment and the friends panel.
    func testSplitScreens() {
        app.launchArguments = ["-uiTesting", "-seedDemo"]
        app.launch()
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 5))
        app.buttons["addButton"].tap()
        XCTAssertTrue(app.buttons["key-9"].waitForExistence(timeout: 5))
        for key in "1800" { app.buttons["key-\(key)"].tap() }
        app.buttons["pick-Food"].tap()
        app.buttons["splitButton"].tap()
        let field = app.textFields["splitFriendField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Rahul\n")
        field.tap()
        field.typeText("Neha\n")
        app.swipeDown(velocity: .slow)
        sleep(1)
        shot("20-split-equal")
        app.buttons["splitMode-percent"].tap()
        let percent = app.textFields["splitPercent-Rahul"]
        if percent.waitForExistence(timeout: 3) {
            percent.tap()
            percent.typeText("50")
        }
        sleep(1)
        shot("21-split-percent")
        app.buttons["splitMode-equal"].tap()
        app.buttons["splitDone"].tap()
        sleep(1)
        shot("22-composer-split")
        app.buttons["saveButton"].tap()
        sleep(1)
        shot("23-ledger-split-row")

        app.openPanel("Friends")
        XCTAssertTrue(app.descendants(matching: .any)["friendsTotal"].firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("24-friends")
        app.descendants(matching: .any)["friend-Rahul"].firstMatch.tap()
        sleep(1)
        shot("25-friend-detail")
    }

    /// Where the delete and paid-back questions open.
    func testDialogs() {
        app.launchArguments = ["-uiTesting", "-seedDemo"]
        app.launch()
        let row = app.descendants(matching: .any)["entry-Swiggy"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["swipeDelete"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        shot("30-delete-dialog")
    }

    func testTour() {
        let sms = "Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 17/10/26\nRef 629012345678\nNot You?"
        app.launchArguments = ["-uiTesting", "-seedDemo", "-simulateSMS", Data(sms.utf8).base64EncodedString()]
        app.launch()
        if !app.buttons["tagQueueButton"].waitForExistence(timeout: 5) {
            // The simulator sometimes already has the app running without these
            // arguments (an empty store); start it again so it gets them.
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.buttons["tagQueueButton"].waitForExistence(timeout: 5))
        sleep(1)
        shot("01-ledger")

        // An uncategorised payment opens in place.
        element("entry-Rapido").tap()
        sleep(1)
        shot("02-inline-tag")
        element("entry-Rapido").tap()

        // Scroll: the strip pins and follows the list.
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("03-scrolled")

        // Scrub back to the start of the month.
        let strip = element("monthStrip")
        let from = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.6))
        let to = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
        from.press(forDuration: 0.4, thenDragTo: to)
        sleep(1)
        shot("04-scrubbed")

        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        sleep(1)

        // Look at one category.
        app.buttons["legend-Groceries"].tap()
        sleep(1)
        shot("05-filtered")
        app.buttons["clearFilter"].tap()

        // Hold + for more.
        app.buttons["addButton"].press(forDuration: 0.8)
        sleep(1)
        shot("06-add-options")
        app.buttons["addExpense"].tap()

        XCTAssertTrue(app.buttons["key-3"].waitForExistence(timeout: 5))
        sleep(1)
        shot("07a-composer-empty")
        for key in "349" { app.buttons["key-\(key)"].tap() }
        app.buttons["pick-Food"].tap()
        sleep(1)
        shot("07-composer")
        app.buttons["pickNewCategory"].tap()
        XCTAssertTrue(app.textFields["newCategoryName"].waitForExistence(timeout: 5))
        app.textFields["newCategoryName"].typeText("Pets")
        shot("07b-new-category")
        app.buttons["popupCancel"].tap()
        app.buttons["addNoteButton"].tap()
        XCTAssertTrue(app.textFields["noteField"].waitForExistence(timeout: 5))
        app.textFields["noteField"].typeText("With the team")
        sleep(1)
        shot("07c-note")
        app.buttons["Cancel"].tap()
        sleep(1)

        element("entry-Bigbasket").tap()
        sleep(1)
        shot("08-edit")
        app.buttons["Cancel"].tap()
        sleep(1)

        // File what's waiting, one card at a time.
        app.buttons["tagQueueButton"].tap()
        XCTAssertTrue(element("triageCard").waitForExistence(timeout: 5))
        sleep(1)
        shot("09-triage")
        app.buttons["tag-Transport"].tap()
        sleep(1)
        shot("09b-triage-next")
        app.buttons["closeTriage"].tap()
        sleep(1)

        app.buttons["setBalanceButton"].tap()
        let balanceField = app.textFields["balanceField"]
        XCTAssertTrue(balanceField.waitForExistence(timeout: 5))
        balanceField.typeText("52340")
        shot("10-balance-editor")
        app.buttons["saveBalanceButton"].tap()
        XCTAssertTrue(element("balanceValue").waitForExistence(timeout: 5))
        sleep(1)
        shot("11-ledger-with-balance")

        app.buttons["monthMenu"].tap()
        sleep(1)
        shot("12-month-menu")
        app.buttons.matching(NSPredicate(format: "label CONTAINS '2026'")).firstMatch.tap()
        sleep(1)

        app.openPanel("Trends")
        XCTAssertTrue(element("trendChart").waitForExistence(timeout: 5))
        sleep(1)
        shot("14a-trends")
        app.buttons["range-3M"].tap()
        sleep(1)
        shot("14b-trends-3m")
        app.buttons["range-Custom"].tap()
        sleep(1)
        shot("14c-trends-custom")
        app.buttons["rangeFrom"].tap()
        sleep(1)
        shot("14c2-trends-calendar")
        app.buttons["rangeFrom"].tap()
        sleep(1)
        app.buttons["range-30D"].tap()
        app.buttons["trend-Food"].tap()
        sleep(1)
        shot("14d-trends-food")
        app.swipeUp()
        sleep(1)
        shot("14e-trends-scrolled")
        back()
        sleep(1)

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        sleep(1)
        shot("13-settings")
        app.buttons["Prompt history"].tap()
        sleep(1)
        shot("13b-prompt-history")
        back()

        app.buttons["Categories"].tap()
        sleep(1)
        shot("14-categories")
        app.staticTexts["Food"].firstMatch.tap()
        sleep(1)
        shot("15-category-editor")
        app.buttons["Cancel"].tap()
        back()

        app.buttons["Auto-log bank SMS"].tap()
        sleep(1)
        shot("16-sms-setup")
        back()

        app.buttons["Test a bank SMS"].tap()
        let field = app.textFields["smsTesterField"].exists ? app.textFields["smsTesterField"] : app.textViews["smsTesterField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("ICICI Bank Acct XX123 debited for Rs 250.00 on 17-Oct-26; SWIGGY credited. UPI:629012345678.")
        sleep(1)
        shot("17-sms-tester")
        back()

        app.buttons["Floating quick-add button"].tap()
        sleep(1)
        shot("18-floating-button")
    }
}
