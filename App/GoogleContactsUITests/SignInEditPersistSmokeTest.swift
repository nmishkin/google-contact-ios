import XCTest

final class SignInEditPersistSmokeTest: XCTestCase {
    func testViewEditAndPersistSeededContact() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()

        let seedRow = app.staticTexts["Seed Person"]
        XCTAssertTrue(seedRow.waitForExistence(timeout: 5))
        seedRow.tap()

        app.buttons["Edit"].tap()
        let firstNameField = app.textFields["First name"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 5))
        firstNameField.tap()
        firstNameField.clearAndTypeText("SeedEdited")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["SeedEdited Person"].waitForExistence(timeout: 5))
    }
}

extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let stringValue = value as? String else { typeText(text); return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        typeText(deleteString)
        typeText(text)
    }
}
