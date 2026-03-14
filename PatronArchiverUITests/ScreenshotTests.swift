import XCTest

final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append("-DemoMode")
        app.launch()

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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "01_MainView"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScreenshotSettingsView() {
        #if os(iOS)
        // iOS: tap gear button to open settings sheet
        let gearButton = app.buttons["Settings"]
        if !gearButton.waitForExistence(timeout: 5) {
            // Fallback: look for gear icon button
            let gearIcon = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'gear' OR label CONTAINS[c] 'setting'")).firstMatch
            XCTAssertTrue(gearIcon.waitForExistence(timeout: 5))
            gearIcon.tap()
        } else {
            gearButton.tap()
        }
        #elseif os(macOS)
        // macOS: open Settings window via keyboard shortcut
        app.typeKey(",", modifierFlags: .command)
        #endif

        // Wait for settings view to appear
        #if os(iOS)
        let settingsContent = app.staticTexts["Accounts"].firstMatch
        XCTAssertTrue(settingsContent.waitForExistence(timeout: 5))
        #elseif os(macOS)
        let settingsWindow = app.windows["PatronArchiver Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        #endif

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "02_SettingsView"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
