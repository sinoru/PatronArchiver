import XCTest

final class PatronArchiverUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launch()
        app.activate()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testURLInputFieldExists() throws {
        let textField = app.textFields["Enter post URL..."]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
    }

    func testAddButtonExists() throws {
        let button = app.buttons["Add"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
    }

    func testEmptyStateShowsNoJobs() throws {
        let noJobs = app.staticTexts["No Jobs"]
        XCTAssertTrue(noJobs.waitForExistence(timeout: 5))
    }
}
