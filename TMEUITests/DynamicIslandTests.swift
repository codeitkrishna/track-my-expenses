import XCTest

/// The category prompt in the Dynamic Island, end to end.
@MainActor
final class DynamicIslandTests: XCTestCase {
    func testFilingFromTheDynamicIsland() throws {
        let sms = "Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 17/10/26\nRef 629012345678\nNot You?"
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-simulateSMS", Data(sms.utf8).base64EncodedString()]
        app.launch()
        XCTAssertTrue(app.buttons["tagQueueButton"].waitForExistence(timeout: 5))

        // The island shows other apps' activities, so step out to the Home Screen.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        sleep(2)
        attach("island-compact", springboard)

        // Press and hold the island to expand it, then tap a category.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        let food = springboard.buttons["Food"].firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 5), "Expanded prompt with category buttons")
        attach("island-expanded", springboard)
        food.tap()
        sleep(1)
        attach("island-filed-1s", springboard)
        sleep(2)
        attach("island-filed-3s", springboard)

        app.activate()
        let queue = app.buttons["tagQueueButton"]
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: queue)], timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any)["entry-Swiggy"].firstMatch.waitForExistence(timeout: 5))
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
