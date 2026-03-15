import XCTest

final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
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

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "01_MainView"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
