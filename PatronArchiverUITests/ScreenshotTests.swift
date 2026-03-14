import XCTest

final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append("-DemoMode")
        app.launch()
        app.activate()

        // Wait for app to fully launch
        let textField = app.textFields["Enter post URL..."]
        XCTAssertTrue(textField.waitForExistence(timeout: 10))

        // Verify demo data loaded (empty state should not appear)
        XCTAssertFalse(app.staticTexts["No Jobs"].exists)
    }

    override func tearDown() async throws {
        app = nil
    }

    func testScreenshotMainView() {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "01_MainView"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
