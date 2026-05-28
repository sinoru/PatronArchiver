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
        let textField = app.textFields["urlInput"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
    }

    func testAddButtonExists() throws {
        let button = app.buttons["addButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
    }

    func testEmptyStateShowsNoJobs() throws {
        let emptyState = app.descendants(matching: .any)["emptyState"].firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
    }
}
