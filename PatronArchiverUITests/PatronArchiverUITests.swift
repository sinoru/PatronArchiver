import XCTest

final class PatronArchiverUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testURLInputFieldExists() throws {
        let app = XCUIApplication()
        app.launch()

        let textField = app.textFields["Enter post URL..."]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
    }

    @MainActor
    func testArchiveButtonExists() throws {
        let app = XCUIApplication()
        app.launch()

        let button = app.buttons["Archive"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptyStateShowsNoJobs() throws {
        let app = XCUIApplication()
        app.launch()

        let noJobs = app.staticTexts["No Jobs"]
        XCTAssertTrue(noJobs.waitForExistence(timeout: 5))
    }
}
