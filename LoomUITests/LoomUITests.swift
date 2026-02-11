import Foundation
import XCTest

final class LoomUITests: XCTestCase {
    private var testRootURL: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let testRootURL {
            try? FileManager.default.removeItem(at: testRootURL)
        }
        testRootURL = nil
    }

    @MainActor
    func testSidebarNavigationShowsCoreScreens() throws {
        let app = launchApp()

        tapSidebarItem("Models", app: app)
        XCTAssertTrue(app.otherElements["screen.models"].waitForExistence(timeout: 2))

        tapSidebarItem("Status", app: app)
        XCTAssertTrue(app.otherElements["screen.status"].waitForExistence(timeout: 2))

        tapSidebarItem("Settings", app: app)
        XCTAssertTrue(app.otherElements["screen.settings"].waitForExistence(timeout: 2))

        tapSidebarItem("Sessions", app: app)
        XCTAssertTrue(app.buttons["sessions.toolbar.new"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCreateRenameAndDeleteSessionFromToolbar() throws {
        let app = launchApp()

        let newSessionButton = app.buttons["sessions.toolbar.new"]
        XCTAssertTrue(newSessionButton.waitForExistence(timeout: 2))
        newSessionButton.click()

        let renameButton = app.buttons["sessions.toolbar.rename"]
        XCTAssertTrue(renameButton.waitForExistence(timeout: 2))
        renameButton.click()

        let renameField = app.textFields["sessions.renameField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 2))
        renameField.click()
        renameField.typeKey("a", modifierFlags: .command)

        let title = "UI Test Session \(UUID().uuidString.prefix(6))"
        renameField.typeText("\(title)\n")

        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 2))

        let deleteButton = app.buttons["sessions.toolbar.delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.click()

        XCTAssertTrue(app.staticTexts["No Session Selected"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSendWithoutModelShowsSetupGuidance() throws {
        let app = launchApp()

        let newSessionButton = app.buttons["sessions.toolbar.new"]
        XCTAssertTrue(newSessionButton.waitForExistence(timeout: 2))
        newSessionButton.click()

        let messageField = app.textFields["session.detail.messageField"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 2))
        messageField.click()
        messageField.typeText("Hello from UI test")

        let sendButton = app.buttons["session.detail.sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 2))
        sendButton.click()

        XCTAssertTrue(app.staticTexts["Choose a model to chat with."].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let testRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LoomUITests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRootURL, withIntermediateDirectories: true)
        self.testRootURL = testRootURL

        let app = XCUIApplication()
        app.launchEnvironment["LOOM_APP_SUPPORT_ROOT"] = testRootURL.path
        app.launchEnvironment["LOOM_UI_TEST_RESET_DEFAULTS"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func tapSidebarItem(_ title: String, app: XCUIApplication) {
        let sidebarCell = app.outlines.cells.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(sidebarCell.waitForExistence(timeout: 2), "Missing sidebar item: \(title)")
        sidebarCell.click()
    }
}
