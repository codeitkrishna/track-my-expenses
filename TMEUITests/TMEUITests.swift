import XCTest

@MainActor
final class TMEUITests: XCTestCase {
    private let swiggySMS = "Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 17/10/26\nRef 629012345678\nNot You?"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Types an amount on the composer's keypad.
    private func enter(_ amount: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["key-1"].waitForExistence(timeout: 5))
        for key in amount { app.buttons["key-\(key)"].tap() }
    }

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extraArguments
        app.launch()
        return app
    }

    private func launchWithSMS() -> XCUIApplication {
        launch(["-simulateSMS", Data(swiggySMS.utf8).base64EncodedString()])
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) {
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)], timeout: timeout)
    }

    func testQuickAddExpense() {
        let app = launch()
        app.buttons["addButton"].tap()

        enter("250", in: app)
        app.buttons["pick-Food"].tap()
        app.buttons["saveButton"].tap()

        XCTAssertTrue(element("entry-Food", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("monthSpent", in: app).label.contains("₹250"))
    }

    func testAddIncomeFromTheHeldAddButton() {
        let app = launch()
        app.buttons["addButton"].press(forDuration: 0.8)
        let income = app.buttons["addIncome"]
        XCTAssertTrue(income.waitForExistence(timeout: 5), "Holding + offers income")
        XCTAssertTrue(app.buttons["addCategory"].exists)
        income.tap()

        enter("500", in: app)
        app.buttons["saveButton"].tap()
        XCTAssertTrue(element("entry-Income", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("monthIn", in: app).label.contains("₹500"))
    }

    func testStartingBalance() {
        let app = launch()
        app.buttons["setBalanceButton"].tap()
        let field = app.textFields["balanceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("10000")
        app.buttons["saveBalanceButton"].tap()

        let balance = element("balanceValue", in: app)
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertTrue(balance.label.contains("₹10,000"))

        // Spending after the balance was set comes off it; the month's net is shown apart.
        app.buttons["addButton"].tap()
        enter("250", in: app)
        app.buttons["pick-Food"].tap()
        app.buttons["saveButton"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹9,750'"), evaluatedWith: balance)], timeout: 5)
        XCTAssertTrue(element("monthSpent", in: app).label.contains("₹250"))
        XCTAssertTrue(element("monthNet", in: app).label.contains("−₹250"))
    }

    func testFilingAnSMSEntryInPlace() {
        let app = launchWithSMS()
        let queue = app.buttons["tagQueueButton"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))

        element("entry-Swiggy", in: app).tap()
        app.buttons["chip-Food"].firstMatch.tap()

        waitUntilGone(queue)
        XCTAssertTrue(element("entry-Swiggy", in: app).label.contains("Food"))
    }

    func testFilingFromTheQueue() {
        let app = launchWithSMS()
        let queue = app.buttons["tagQueueButton"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        queue.tap()

        XCTAssertTrue(element("triageCard", in: app).waitForExistence(timeout: 5))
        app.buttons["tag-Food"].tap()
        XCTAssertTrue(element("allFiled", in: app).waitForExistence(timeout: 5))

        // The queue closes itself once everything is filed.
        XCTAssertTrue(element("entry-Swiggy", in: app).waitForExistence(timeout: 5))
        waitUntilGone(queue)
        XCTAssertTrue(element("entry-Swiggy", in: app).label.contains("Food"))
    }

    func testPromptHistoryRecordsWhatHappened() {
        let app = launchWithSMS()
        XCTAssertTrue(app.buttons["tagQueueButton"].waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()
        app.buttons["Prompt history"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '₹250 out: needs a category.'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Asked in the Dynamic Island.'")).firstMatch.exists)
    }

    func testNoteWhileAddingAnExpense() {
        let app = launch()
        app.buttons["addButton"].tap()
        enter("90", in: app)
        app.buttons["addNoteButton"].tap()

        let note = app.textFields["noteField"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "Tapping Note opens the note field")
        note.typeText("Chai\n")
        app.buttons["saveButton"].tap()
        XCTAssertTrue(element("entry-Chai", in: app).waitForExistence(timeout: 5))
    }

    func testPastReceiversAreSuggested() {
        let app = launch(["-seedDemo"])
        app.buttons["addButton"].tap()
        enter("150", in: app)

        let receiver = app.textFields["receiverField"]
        XCTAssertTrue(receiver.waitForExistence(timeout: 5))
        receiver.tap()
        receiver.typeText("s")
        XCTAssertFalse(app.buttons["suggest-Swiggy"].exists, "No suggestions after one letter")
        receiver.typeText("W")
        let swiggy = app.buttons["suggest-Swiggy"]
        XCTAssertTrue(swiggy.waitForExistence(timeout: 5), "Two letters, any case, suggest a past receiver")
        swiggy.tap()

        XCTAssertEqual(receiver.value as? String, "Swiggy")
        XCTAssertTrue(app.buttons["pick-Food"].isSelected, "Their usual category comes with them")
        app.buttons["saveButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'entry-Swiggy' AND label CONTAINS '₹150'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testNewCategoryWhileAddingAnExpense() {
        let app = launch()
        app.buttons["addButton"].tap()
        enter("120", in: app)
        app.buttons["pickNewCategory"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Pets")
        app.alerts.buttons["Create"].tap()

        let pets = app.buttons["pick-Pets"]
        XCTAssertTrue(pets.waitForExistence(timeout: 5))
        XCTAssertTrue(pets.isSelected, "The new category is picked for this expense")
        app.buttons["saveButton"].tap()
        XCTAssertTrue(element("entry-Pets", in: app).waitForExistence(timeout: 5))
    }

    func testNewCategoryForAnSMSEntry() {
        let app = launchWithSMS()
        let queue = app.buttons["tagQueueButton"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        element("entry-Swiggy", in: app).tap()
        app.buttons["newCategoryChip"].firstMatch.tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Eating out")
        app.alerts.buttons["Create"].tap()

        waitUntilGone(queue)
        XCTAssertTrue(element("entry-Swiggy", in: app).label.contains("Eating out"))
    }

    func testMonthOverviewAndCategoryFilter() {
        let app = launch(["-seedDemo"])
        XCTAssertTrue(element("monthStrip", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry-Uber", in: app).exists)

        app.buttons["legend-Groceries"].tap()
        XCTAssertTrue(app.buttons["clearFilter"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("entry-Bigbasket", in: app).exists)
        XCTAssertFalse(element("entry-Uber", in: app).exists, "Only Groceries payments while Groceries is picked")

        app.buttons["clearFilter"].tap()
        XCTAssertTrue(element("entry-Uber", in: app).waitForExistence(timeout: 5))
    }

    func testScrubbingTheMonthMovesTheList() {
        let app = launch(["-seedDemo"])
        let strip = element("monthStrip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        let today = strip.value as? String ?? ""

        // Drag from today's end of the strip back to its first days.
        let start = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: end)
        let scrubbed = strip.value as? String ?? ""
        XCTAssertNotEqual(today, scrubbed, "The marker moved to another day")
    }
}
