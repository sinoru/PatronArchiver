import XCTest

final class PatronArchiverUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testURLInputFieldExists() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()

        let textField = app.textFields["Enter post URL..."]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
    }

    func testAddButtonExists() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()

        let button = app.buttons["Add"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
    }

    func testEmptyStateShowsNoJobs() throws {
        let app = XCUIApplication()
        app.launch()
        app.activate()

        let noJobs = app.staticTexts["No Jobs"]
        XCTAssertTrue(noJobs.waitForExistence(timeout: 5))
    }
}
