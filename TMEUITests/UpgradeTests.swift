import XCTest

/// Splitting on a database made by an earlier version, upgraded in place.
/// Runs against the app's real on-disk store, so it's skipped unless run
/// with TEST_RUNNER_TME_UPGRADE=1 after installing the older build first.
@MainActor
final class UpgradeTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TME_UPGRADE"] != nil, "Upgrade check not requested")
        continueAfterFailure = false
    }

    func testSplittingAnOlderPayment() {
        let app = XCUIApplication()
        app.launch()
        let row = app.descendants(matching: .any)["entry-Bigbasket"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Payments from the older version are still there")
        row.tap()

        app.buttons["splitButton"].tap()
        let field = app.textFields["splitFriendField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Prakhar\n")
        app.buttons["splitDone"].tap()
        app.buttons["saveButton"].tap()

        app.buttons["friendsButton"].tap()
        let friend = app.descendants(matching: .any)["friend-Prakhar"].firstMatch
        XCTAssertTrue(friend.waitForExistence(timeout: 5), "The split was saved in the upgraded store")
    }
}
