import XCTest

final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-DemoMode")
        app.launch()
        return app
    }

    func testScreenshotMainView() {
        let app = launchApp()

        // Wait for demo data to appear
        let firstJob = app.staticTexts["Monthly Illustration Pack - December"]
        XCTAssertTrue(firstJob.waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "01_MainView"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScreenshotSettingsView() {
        let app = launchApp()

        // Wait for demo data to load
        let firstJob = app.staticTexts["Monthly Illustration Pack - December"]
        XCTAssertTrue(firstJob.waitForExistence(timeout: 10))

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
        let settingsContent = app.staticTexts["Accounts"].firstMatch
        XCTAssertTrue(settingsContent.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "02_SettingsView"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
