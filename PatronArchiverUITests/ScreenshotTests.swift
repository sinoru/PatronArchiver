import XCTest

final class ScreenshotTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-ApplePersistenceIgnoreState", "YES"])
        app.launchArguments.append("-DemoMode")
        app.launch()
        app.activate()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testScreenshotMainView() {
        // Wait for app to fully launch
        let textField = app.textFields["Enter post URL..."]
        XCTAssertTrue(textField.waitForExistence(timeout: 10))

        // Verify demo data loaded (empty state should not appear)
        XCTAssertFalse(app.staticTexts["No Jobs"].exists)

        let appAttachment = XCTAttachment(screenshot: app.screenshot())
        appAttachment.name = "App"
        appAttachment.lifetime = .keepAlways
        add(appAttachment)

        #if os(macOS)
        let window = app.windows["PatronArchiver"]
        let windowAttachment = XCTAttachment(screenshot: window.screenshot())
        windowAttachment.name = "PatronArchiver Window"
        windowAttachment.lifetime = .keepAlways
        add(windowAttachment)
        #endif
    }
}
