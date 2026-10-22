import XCTest

extension XCUIApplication {
    /// Opens Trends, Friends or Goals: hold the top-left button, pick one.
    func openPanel(_ title: String) {
        let button = buttons["panelsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.press(forDuration: 1.0)
        let item = buttons[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(title) in the panel menu")
        item.tap()
    }
}
