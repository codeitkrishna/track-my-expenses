import XCTest

/// Goals end to end: the screens, setting money aside, spending from a
/// goal, and the payday and category prompts in the Dynamic Island.
@MainActor
final class GoalsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    /// Attached always; also written to TME_SHOTS_DIR when it's set.
    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["TME_SHOTS_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func launch(_ arguments: [String] = ["-seedGoals"]) {
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
    }

    private func back() {
        let buttons = app.navigationBars.firstMatch.buttons.allElementsBoundByIndex
        buttons.min { $0.frame.minX < $1.frame.minX }?.tap()
    }

    private func type(_ amount: String) {
        XCTAssertTrue(app.buttons["key-1"].waitForExistence(timeout: 5))
        for key in amount { app.buttons["key-\(key)"].tap() }
    }

    func testGoalsScreenAndPayday() {
        launch()
        XCTAssertTrue(element("goalsLine").waitForExistence(timeout: 5), "Money in goals shows under free to spend")
        XCTAssertTrue(element("balanceValue").label.contains("Free to spend"))
        shot("goals-01-main")

        app.openPanel("Goals")
        XCTAssertTrue(element("goal-Goa trip").waitForExistence(timeout: 5))
        XCTAssertTrue(element("goal-New camera").exists)
        XCTAssertTrue(element("goal-Rainy-day fund").exists)
        XCTAssertTrue(element("paydayCard").exists, "Today's salary waits to feed the goals")
        sleep(2)
        shot("goals-02-list")

        let setAside = element("goalsSetAside")
        let before = setAside.label
        app.buttons["paydayAccept"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element("paydayCard"))], timeout: 5)
        XCTAssertNotEqual(setAside.label, before, "Payday money went into the goals")

        app.swipeUp()
        XCTAssertTrue(element("done-Ladakh ride").waitForExistence(timeout: 5), "The finished goal is on the shelf")
        sleep(1)
        shot("goals-03-shelf")
    }

    func testGoalDetailAddAndTakeOut() {
        launch()
        app.openPanel("Goals")
        element("goal-Goa trip").tap()
        XCTAssertTrue(element("departureBoard").waitForExistence(timeout: 5))
        sleep(2)
        shot("goals-04-detail")

        let amount = element("goalAmount")
        let before = amount.label
        app.buttons["addToGoal"].tap()
        type("5000")
        shot("goals-05-add")
        app.buttons["saveGoalMoney"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label != %@", before), evaluatedWith: amount)], timeout: 5)

        app.buttons["takeOutOfGoal"].tap()
        type("5000")
        app.buttons["saveGoalMoney"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label == %@", before), evaluatedWith: amount)], timeout: 5)

        app.swipeUp()
        sleep(1)
        shot("goals-06-rules")
        app.swipeUp()
        sleep(1)
        shot("goals-07-history")
    }

    func testCreatingAGoal() {
        launch([])
        app.openPanel("Goals")
        XCTAssertTrue(app.buttons["firstGoalButton"].waitForExistence(timeout: 5))
        shot("goals-08-empty")
        app.buttons["firstGoalButton"].tap()
        let name = app.textFields["goalNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Concert tickets")
        app.textFields["goalAmountField"].tap()
        app.textFields["goalAmountField"].typeText("12000")
        shot("goals-09-editor")
        app.buttons["saveGoalButton"].tap()
        let card = element("goal-Concert tickets")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("₹12,000"))
        XCTAssertTrue((card.value as? String ?? "").contains("Learning"), "No pace yet with no payments")
    }

    func testPickingAPhoto() throws {
        launch([])
        app.openPanel("Goals")
        app.buttons["firstGoalButton"].tap()
        XCTAssertTrue(app.textFields["goalNameField"].waitForExistence(timeout: 5))
        app.textFields["goalNameField"].typeText("Waterfall trek")
        app.textFields["goalAmountField"].tap()
        app.textFields["goalAmountField"].typeText("8000")
        app.buttons["goalPhotoButton"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,'")).firstMatch
        guard photo.waitForExistence(timeout: 10) else {
            throw XCTSkip("The simulator's photo library is empty")
        }
        photo.tap()
        sleep(2)
        shot("goals-10-photo-picked")
        app.buttons["saveGoalButton"].tap()
        XCTAssertTrue(element("goal-Waterfall trek").waitForExistence(timeout: 5))
        sleep(1)
        shot("goals-11-photo-card")
    }

    func testSpendingFromAGoal() {
        launch()
        let balance = element("balanceValue")
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        let free = balance.label
        app.openPanel("Goals")
        element("goal-Goa trip").tap()
        app.buttons["spendFromGoal"].tap()
        app.buttons["Until I stop"].tap()
        XCTAssertTrue(app.buttons["stopSpending"].waitForExistence(timeout: 5))
        sleep(1)
        shot("goals-12-spending")
        back()
        back()

        // A payment added now comes out of the trip.
        app.buttons["addButton"].tap()
        type("1500")
        XCTAssertTrue(app.buttons["goalButton"].label.contains("Goa trip"), "The goal being spent from is picked already")
        // No rule takes a share of Transport, so nothing else moves.
        app.buttons["pick-Transport"].tap()
        sleep(1)
        shot("goals-13-composer")
        app.buttons["saveButton"].tap()
        let row = element("entry-Transport")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("From Goa trip"))
        XCTAssertEqual(balance.label, free, "Spending from a goal leaves free money alone")
    }

    func testPaydayInTheDynamicIsland() {
        let sms = "Dear Customer, Acct XX123 is credited with Rs 85,000.00 on 22-Oct-26 from ACME PVT LTD. UPI:629055555555-ICICI Bank."
        launch(["-seedGoals", "-simulateSMS", Data(sms.utf8).base64EncodedString()])
        XCTAssertTrue(element("goalsLine").waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        sleep(2)
        shot("goals-14-island-compact")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        let setAside = springboard.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Set aside'")).firstMatch
        let shown = setAside.waitForExistence(timeout: 5)
        shot("goals-15-island-payday")
        XCTAssertTrue(shown, "Expanded payday prompt")
        setAside.tap()
        sleep(1)
        shot("goals-16-island-fed")

        app.activate()
        XCTAssertTrue(app.buttons["panelsButton"].waitForExistence(timeout: 5))
        app.openPanel("Goals")
        XCTAssertTrue(element("goal-Goa trip").waitForExistence(timeout: 5))
        element("goal-Goa trip").tap()
        XCTAssertTrue(element("departureBoard").waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Of ₹85,000 from Acme'")).count >= 4,
                      "Three old paydays and this one")
    }

    func testCategoryPromptMeasuresInTheGoal() {
        let sms = "Sent Rs.1450.00\nFrom HDFC Bank A/C *1234\nTo SOCIAL\nOn 22/10/26\nRef 629077777777\nNot You?"
        launch(["-seedGoals", "-simulateSMS", Data(sms.utf8).base64EncodedString()])
        XCTAssertTrue(app.buttons["tagQueueButton"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        sleep(2)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        XCTAssertTrue(springboard.buttons["Food"].firstMatch.waitForExistence(timeout: 5))
        shot("goals-17-island-yardstick")
        let line = springboard.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS 'of saving for Goa trip'")).firstMatch
        XCTAssertTrue(line.exists, "The island says what it costs in the goal")
        springboard.buttons["Food"].firstMatch.tap()
        sleep(1)
    }

    func testCategoryLimitShowsWhatGoingOverCostsTheGoal() {
        launch()
        // A tap opens the last panel used, Goals to begin with.
        XCTAssertTrue(app.buttons["panelsButton"].waitForExistence(timeout: 5))
        app.buttons["panelsButton"].tap()
        XCTAssertTrue(element("goal-Goa trip").waitForExistence(timeout: 5))
        back()

        app.buttons["settingsButton"].tap()
        app.buttons["Categories"].tap()
        element("category-Food").tap()
        // The demo has Food limits per day and week already; the month is free.
        let monthly = app.textFields["limit-month"]
        XCTAssertTrue(monthly.waitForExistence(timeout: 5))
        monthly.tap()
        monthly.typeText("100")
        shot("goals-18-limit-editor")
        app.buttons["Save"].tap()
        back()
        app.buttons["settingsDone"].tap()

        let row = element("limit-Food-month")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("over this month's ₹100"), row.label)
        XCTAssertTrue(row.label.contains("Goa trip is"), "What it costs the goal: \(row.label)")
        sleep(1)
        shot("goals-19-limits")
    }

    /// A new goal has no pace yet, and its board says so at length; the page
    /// must still fit the screen.
    func testNewGoalPageFitsTheScreen() {
        launch([])
        app.openPanel("Goals")
        app.buttons["firstGoalButton"].tap()
        XCTAssertTrue(app.textFields["goalNameField"].waitForExistence(timeout: 5))
        app.textFields["goalNameField"].typeText("Bike Mods")
        app.textFields["goalAmountField"].tap()
        app.textFields["goalAmountField"].typeText("9000")
        app.buttons["saveGoalButton"].tap()
        element("goal-Bike Mods").tap()
        let board = element("departureBoard")
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        sleep(2)
        shot("goals-20-new-goal-page")
        let screen = app.windows.firstMatch.frame
        let detail = element("goalAmountDetail")
        XCTAssertGreaterThanOrEqual(detail.frame.minX, screen.minX + 16, "The page keeps its margin: \(detail.frame) in \(screen)")
        let status = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'learning your pace'")).firstMatch
        XCTAssertTrue(status.exists)
        XCTAssertLessThanOrEqual(status.frame.maxX, screen.maxX - 16, "The board's status fits: \(status.frame) in \(screen)")
    }

    func testFanAndCategoriesPage() {
        launch()
        let button = app.buttons["panelsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Categories"].waitForExistence(timeout: 5), "The fan is open")
        sleep(1)
        shot("cat-01-fan")
        app.buttons["Categories"].tap()

        let food = element("tile-Food")
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        sleep(1)
        shot("cat-02-month")
        app.buttons["period-week"].tap()
        sleep(1)
        XCTAssertTrue(food.label.contains("over"), food.label)
        shot("cat-03-week")
        food.tap()
        XCTAssertTrue(element("categorySpent").waitForExistence(timeout: 5))
        sleep(1)
        shot("cat-04-food")
        app.swipeUp()
        sleep(1)
        shot("cat-05-food-payments")
    }

    /// Every fan and a confirmation card, for a look.
    func testFansAndCards() {
        launch()
        let add = app.buttons["addButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["addIncome"].waitForExistence(timeout: 5))
        sleep(1)
        shot("fan-02-add")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.95)).tap()

        let panels = app.buttons["panelsButton"]
        panels.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Goals"].waitForExistence(timeout: 5))
        sleep(1)
        shot("fan-01-panels")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()

        app.swipeUp()
        sleep(1)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entry-'")).allElementsBoundByIndex
        // One in the middle of the screen, clear of the pinned strip and the dock.
        let screen = app.windows.firstMatch.frame
        guard let row = rows.first(where: { $0.isHittable && $0.frame.midY > screen.height * 0.4 && $0.frame.midY < screen.height * 0.75 }) else {
            return XCTFail("No payment in the middle of the screen")
        }
        row.swipeLeft()
        XCTAssertTrue(app.buttons["swipeDelete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["swipeDelete"].firstMatch.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        sleep(1)
        shot("fan-04-confirm")
        app.buttons["popupCancel"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Cancel keeps the payment")
    }
}
