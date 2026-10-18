import XCTest

/// Scroll smoothness of the main screen with a heavy month. Measured as hitch
/// time (ms of dropped frames per second of scrolling); lower is smoother.
/// Skipped unless run with TEST_RUNNER_TME_PERF=1 set for xcodebuild.
@MainActor
final class ScrollPerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TME_PERF"] != nil, "Performance run not requested")
    }

    /// One pass of the same scrolling, for counting view updates in the log.
    func testLedgerScrollOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedLots"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["monthStrip"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        sleep(2)
    }

    func testLedgerScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedLots"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["monthStrip"].firstMatch.waitForExistence(timeout: 10))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollDraggingMetric], options: options) {
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
    }
}
