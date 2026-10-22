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

    func testShortHoldOpensTheMenuAndTapAddsAnExpense() {
        let app = launch()
        let add = app.buttons["addButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.press(forDuration: 0.5)
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 3), "A short hold opens the menu")
        add.tap()
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["addExpense"].exists, "Tapping × closes it")
        add.tap()
        XCTAssertTrue(app.buttons["key-1"].waitForExistence(timeout: 5), "A tap goes straight to a new expense")
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

        // The queue confirms briefly and closes itself once everything is filed.
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
        let name = app.textFields["newCategoryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Pets")
        app.buttons["popupConfirm"].tap()

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
        let name = app.textFields["newCategoryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Eating out")
        app.buttons["popupConfirm"].tap()

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

    func testTrendsOverAnyRange() {
        let app = launch(["-seedDemo"])
        app.openPanel("Trends")
        XCTAssertTrue(element("trendChart", in: app).waitForExistence(timeout: 5))
        let total = element("trendTotal", in: app)
        let lastThirtyDays = total.label

        app.buttons["range-7D"].tap()
        let changed = NSPredicate(format: "label != %@", lastThirtyDays)
        wait(for: [expectation(for: changed, evaluatedWith: total)], timeout: 5)

        app.buttons["range-Custom"].tap()
        XCTAssertTrue(element("rangeFrom", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("rangeTo", in: app).exists)

        app.buttons["trend-Food"].tap()
        XCTAssertTrue(app.buttons["trendShowAll"].waitForExistence(timeout: 5), "Following one category")
    }

    func testSplittingWithFriends() {
        let app = launch()
        app.buttons["addButton"].tap()
        enter("900", in: app)
        app.buttons["splitButton"].tap()

        let field = app.textFields["splitFriendField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Prakhar\n")
        field.tap()
        field.typeText("Riya\n")
        XCTAssertTrue(element("splitStatus", in: app).label.contains("₹600 owed to you by 2 friends"))
        app.buttons["splitDone"].tap()
        XCTAssertTrue(app.buttons["splitButton"].label.contains("Split · 2"))
        app.buttons["saveButton"].tap()

        // The friends panel: Prakhar owes his third.
        app.openPanel("Friends")
        XCTAssertTrue(element("friendsTotal", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("friendsTotal", in: app).label.contains("₹600"))
        element("friend-Prakhar", in: app).tap()
        XCTAssertTrue(element("friendOwed", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("friendOwed", in: app).label.contains("₹300"))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'of ₹900'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["shareOwed"].waitForExistence(timeout: 5), "A picture to share")

        // Lend him ₹200 more from his page.
        app.buttons["addForFriend"].tap()
        enter("200", in: app)
        app.buttons["saveButton"].tap()
        let owed = element("friendOwed", in: app)
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹500'"), evaluatedWith: owed)], timeout: 5)

        // He pays back one, then everything.
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'paid-'")).firstMatch.tap()
        app.buttons["Mark as paid"].firstMatch.tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹300' OR label CONTAINS '₹200'"), evaluatedWith: owed)], timeout: 5)
        app.buttons["settleAll"].tap()
        app.buttons["Mark everything as paid"].firstMatch.tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹0'"), evaluatedWith: owed)], timeout: 5)
    }

    func testDeletingAPaymentBySwiping() {
        let app = launch(["-seedDemo"])
        let row = element("entry-Swiggy", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let uberRows = app.descendants(matching: .any).matching(identifier: "entry-Swiggy").count
        row.swipeLeft()
        let delete = app.buttons["swipeDelete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "Swiping left shows Delete")
        // A finger on the revealed button (the slid row's accessibility
        // frame still claims this spot, so a plain tap() calls it hidden).
        delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Delete"].firstMatch.tap()
        let fewer = NSPredicate(format: "count == %d", uberRows - 1)
        wait(for: [expectation(for: fewer, evaluatedWith: app.descendants(matching: .any).matching(identifier: "entry-Swiggy"))], timeout: 5)
    }

    func testDeletingAPaymentFromAFriend() {
        let app = launch()
        // Dinner split with Prakhar (₹300 his)...
        app.buttons["addButton"].tap()
        enter("600", in: app)
        app.buttons["splitButton"].tap()
        let field = app.textFields["splitFriendField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Prakhar\n")
        app.buttons["splitDone"].tap()
        app.buttons["saveButton"].tap()
        // ...and ₹200 lent to him, added from his page.
        app.openPanel("Friends")
        element("friend-Prakhar", in: app).tap()
        app.buttons["addForFriend"].tap()
        enter("200", in: app)
        app.buttons["saveButton"].tap()
        let owed = element("friendOwed", in: app)
        XCTAssertTrue(owed.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹500'"), evaluatedWith: owed)], timeout: 5)

        // Delete the loan altogether: gone from his account and from the tracker.
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'share-'"))
        XCTAssertEqual(rows.count, 2)
        rows.element(boundBy: 0).swipeLeft()
        app.buttons["swipeRemove"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Delete payment"].firstMatch.tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹300'"), evaluatedWith: owed)], timeout: 5)

        // Take the dinner off his account but keep the payment.
        rows.element(boundBy: 0).swipeLeft()
        app.buttons["swipeRemove"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Only remove from Prakhar"].firstMatch.tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹0'"), evaluatedWith: owed)], timeout: 5)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("monthSpent", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("monthSpent", in: app).label.contains("₹600"), "The dinner stays; the loan is gone")
    }

    func testEditingAFriendsPaymentChangesTheSplit() {
        let app = launch()
        app.openPanel("Friends")
        app.buttons["addFriendButton"].tap()
        let name = app.textFields["friendNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Prakash")
        app.buttons["popupConfirm"].tap()
        element("friend-Prakash", in: app).tap()
        app.buttons["addForFriend"].tap()
        enter("400", in: app)
        app.buttons["saveButton"].tap()
        let owed = element("friendOwed", in: app)
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹400'"), evaluatedWith: owed)], timeout: 5)

        // Open it, make it 50/50 and give it a category.
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'open-'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["splitButton"].waitForExistence(timeout: 5))
        app.buttons["splitButton"].tap()
        element("splitIncludesMe", in: app).tap()
        XCTAssertTrue(element("splitStatus", in: app).label.contains("₹200 owed to you"))
        app.buttons["splitDone"].tap()
        app.buttons["pick-Food"].tap()
        app.buttons["saveButton"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '₹200'"), evaluatedWith: owed)], timeout: 5)
    }

    func testQueueFilesOneCardAtATime() {
        let app = launch()
        // Two payments to the same person, both waiting for a category.
        for amount in ["100", "250"] {
            app.buttons["addButton"].tap()
            enter(amount, in: app)
            let receiver = app.textFields["receiverField"]
            receiver.tap()
            receiver.typeText("Prakhar\n")
            app.buttons["saveButton"].tap()
        }
        let queue = app.buttons["tagQueueButton"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        queue.tap()
        XCTAssertTrue(element("triageCard", in: app).waitForExistence(timeout: 5))
        app.buttons["tag-Food"].tap()

        // Only the top card was filed; the other one is next.
        XCTAssertTrue(app.staticTexts["Last one"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("triageCard", in: app).exists)
        app.buttons["tag-Transport"].tap()
        XCTAssertTrue(element("allFiled", in: app).waitForExistence(timeout: 5) || !queue.exists)
    }

    func testScrollingStartsOnTheStrip() {
        let app = launch(["-seedLots"])
        let hero = element("monthSpent", in: app)
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        sleep(1)
        let top = hero.frame.minY

        // A thumb dragging up from the strip, at thumb speed.
        let from = element("monthStrip", in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.02, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -260)), withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssertLessThan(hero.frame.minY, top - 100, "Dragging up from the strip scrolls the page")

        // And back down, starting on the strip while it's pinned.
        let pinned = element("monthStrip", in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        pinned.press(forDuration: 0.02, thenDragTo: pinned.withOffset(CGVector(dx: 0, dy: 300)), withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssertGreaterThan(hero.frame.minY, top - 100, "Dragging down from the pinned strip scrolls back up")
    }

    func testScrollingOverPaymentsDoesNotOpenThem() {
        let app = launch(["-seedLots"])
        XCTAssertTrue(element("monthSpent", in: app).waitForExistence(timeout: 10))
        sleep(1)
        let hero = element("monthSpent", in: app)
        // Thumb-speed drags that start on payment rows, up then down, some
        // drifting sideways the way a thumb arcs.
        for (dx, dy) in [(0.0, -220.0), (40.0, -200.0), (-35.0, 180.0), (30.0, -160.0), (0.0, 200.0)] {
            let before = hero.frame.minY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: dy < 0 ? 0.75 : 0.45))
            start.press(forDuration: 0.03, thenDragTo: start.withOffset(CGVector(dx: dx, dy: dy)), withVelocity: .slow, thenHoldForDuration: 0.05)
            sleep(1)
            XCTAssertFalse(app.buttons["saveButton"].exists, "Scrolling over a payment (\(dx), \(dy)) doesn't open it")
            XCTAssertNotEqual(hero.frame.minY, before, "The page scrolled (\(dx), \(dy))")
            if app.buttons["saveButton"].exists { app.buttons["Cancel"].tap() }
        }
    }

    func testDeletingFromTheEditor() {
        let app = launch(["-seedDemo"])
        let row = element("entry-Bigbasket", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let before = app.descendants(matching: .any).matching(identifier: "entry-Bigbasket").count
        row.tap()
        app.buttons["Delete"].firstMatch.tap()
        let confirm = app.buttons["confirmDeletePayment"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "The trash button asks first")
        confirm.tap()
        let fewer = NSPredicate(format: "count == %d", before - 1)
        wait(for: [expectation(for: fewer, evaluatedWith: app.descendants(matching: .any).matching(identifier: "entry-Bigbasket"))], timeout: 5)
    }

    func testScrubbingTheMonthMovesTheList() {
        let app = launch(["-seedDemo"])
        let strip = element("monthStrip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        let today = strip.value as? String ?? ""

        // Drag from today's end of the strip back to its first days.
        let start = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.6))
        start.press(forDuration: 0.4, thenDragTo: end)
        let scrubbed = strip.value as? String ?? ""
        XCTAssertNotEqual(today, scrubbed, "The marker moved to another day")
    }
}
