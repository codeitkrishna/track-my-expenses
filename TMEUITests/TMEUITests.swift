import XCTest

@MainActor
final class TMEUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extraArguments
        app.launch()
        return app
    }

    func testQuickAddExpense() {
        let app = launch()
        app.buttons["addButton"].tap()

        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("250")
        app.buttons["pick-Food"].tap()
        app.buttons["saveButton"].tap()

        let row = app.descendants(matching: .any)["entry-Food"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["₹250"].exists)
        XCTAssertTrue(app.staticTexts.matching(identifier: "monthSpent").firstMatch.label.contains("Spent, ₹250"))
    }

    func testStartingBalance() {
        let app = launch()
        app.buttons["setBalanceButton"].tap()
        let field = app.textFields["balanceField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("10000")
        app.buttons["saveBalanceButton"].tap()

        let balance = app.descendants(matching: .any)["balanceValue"].firstMatch
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertTrue(balance.label.contains("₹10,000"))

        // Spending after the balance was set comes off it.
        app.buttons["addButton"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
        app.textFields["amountField"].typeText("250")
        app.buttons["pick-Food"].tap()
        app.buttons["saveButton"].tap()
        let updated = NSPredicate(format: "label CONTAINS '₹9,750'")
        wait(for: [expectation(for: updated, evaluatedWith: balance)], timeout: 5)
    }

    func testFilingAnSMSEntryFromActivity() {
        let sms = "Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 17/10/26\nRef 629012345678\nNot You?"
        let app = launch(["-simulateSMS", Data(sms.utf8).base64EncodedString()])

        XCTAssertTrue(app.staticTexts["Needs a category"].waitForExistence(timeout: 5))
        app.buttons["chip-Food"].firstMatch.tap()

        let header = app.staticTexts["Needs a category"]
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: header)
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["entry-Swiggy"].firstMatch.waitForExistence(timeout: 5))
    }

    func testDashboardShowsTheMonth() {
        let app = launch(["-seedDemo", "-tab", "dashboard"])
        XCTAssertTrue(app.staticTexts["Where it went"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Day by day"].exists)
    }
}
