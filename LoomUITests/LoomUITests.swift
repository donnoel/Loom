import Foundation
import XCTest

final class LoomUITests: XCTestCase {
    private static let shortTimeout: TimeInterval = 2
    private static let mediumTimeout: TimeInterval = 5
    private static let longTimeout: TimeInterval = 12

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

        tapSidebarItem(identifier: "sidebar.models", title: "Models", app: app)
        XCTAssertTrue(element("root.detail.models", app: app).waitForExistence(timeout: Self.mediumTimeout))

        tapSidebarItem(identifier: "sidebar.status", title: "Status", app: app)
        XCTAssertTrue(element("root.detail.status", app: app).waitForExistence(timeout: Self.mediumTimeout))

        tapSidebarItem(identifier: "sidebar.settings", title: "Settings", app: app)
        XCTAssertTrue(element("root.detail.settings", app: app).waitForExistence(timeout: Self.mediumTimeout))

        tapSidebarItem(identifier: "sidebar.sessions", title: "Sessions", app: app)
        XCTAssertTrue(button("sessions.toolbar.new", app: app).waitForExistence(timeout: Self.shortTimeout))
        XCTAssertTrue(element("root.detail.sessions", app: app).waitForExistence(timeout: Self.shortTimeout))
    }

    @MainActor
    func testCreateRenameAndDeleteSessionFromToolbar() throws {
        let app = launchApp()
        tapSidebarItem(identifier: "sidebar.sessions", title: "Sessions", app: app)
        XCTAssertTrue(element("root.detail.sessions", app: app).waitForExistence(timeout: Self.shortTimeout))

        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        let renameButton = button("sessions.toolbar.rename", app: app)
        if !waitForEnabled(renameButton, timeout: Self.shortTimeout) {
            let newSessionTitle = app.staticTexts["New Session"].firstMatch
            if newSessionTitle.waitForExistence(timeout: Self.shortTimeout) {
                newSessionTitle.click()
            }
        }
        XCTAssertTrue(waitForEnabled(renameButton, timeout: Self.mediumTimeout))
        renameButton.click()

        let renameField = element("sessions.renameField", app: app)
        XCTAssertTrue(renameField.waitForExistence(timeout: Self.mediumTimeout))
        renameField.click()
        renameField.typeKey("a", modifierFlags: .command)

        let title = "UI Test Session \(UUID().uuidString.prefix(6))"
        renameField.typeText("\(title)\n")

        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: Self.mediumTimeout))

        let deleteButton = button("sessions.toolbar.delete", app: app)
        XCTAssertTrue(waitForEnabled(deleteButton, timeout: Self.mediumTimeout))
        deleteButton.click()

        XCTAssertTrue(app.staticTexts["No Session Selected"].waitForExistence(timeout: Self.mediumTimeout))
    }

    @MainActor
    func testSendWithoutModelShowsSetupGuidance() throws {
        let app = launchApp()
        tapSidebarItem(identifier: "sidebar.sessions", title: "Sessions", app: app)
        XCTAssertTrue(element("root.detail.sessions", app: app).waitForExistence(timeout: Self.shortTimeout))

        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        let messageField = element("session.detail.messageField", app: app)
        XCTAssertTrue(messageField.waitForExistence(timeout: Self.mediumTimeout))
        messageField.click()
        messageField.typeText("Hello from UI test")

        clickButton("session.detail.sendButton", app: app)

        XCTAssertTrue(app.staticTexts["Choose a model to chat with."].waitForExistence(timeout: Self.mediumTimeout))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let testRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LoomUITests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRootURL, withIntermediateDirectories: true)
        self.testRootURL = testRootURL

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LOOM_APP_SUPPORT_ROOT"] = testRootURL.path
        app.launchEnvironment["LOOM_UI_TEST_RESET_DEFAULTS"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Self.mediumTimeout))
        return app
    }

    @MainActor
    private func tapSidebarItem(identifier: String, title: String, app: XCUIApplication) {
        ensureSidebarVisible(app: app)

        let identifiedSidebarItem = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        if identifiedSidebarItem.waitForExistence(timeout: Self.mediumTimeout) {
            identifiedSidebarItem.click()
            return
        }

        let titledSidebarItem = app.outlines.staticTexts[title].firstMatch
        if titledSidebarItem.waitForExistence(timeout: Self.mediumTimeout) {
            titledSidebarItem.click()
            return
        }

        let fallbackItem = app.staticTexts[title].firstMatch
        if fallbackItem.waitForExistence(timeout: Self.shortTimeout) {
            fallbackItem.click()
            return
        }

        XCTFail("Missing sidebar item: \(title)")
    }

    @MainActor
    private func button(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .button)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func element(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func ensureSidebarVisible(app: XCUIApplication) {
        let sessionsSidebarItem = app.descendants(matching: .any)
            .matching(identifier: "sidebar.sessions")
            .firstMatch
        let modelsSidebarItemByTitle = app.outlines.staticTexts["Models"].firstMatch
        if sessionsSidebarItem.waitForExistence(timeout: 1)
            || modelsSidebarItemByTitle.waitForExistence(timeout: 1) {
            return
        }

        app.typeKey("s", modifierFlags: [.command, .option])
        _ = sessionsSidebarItem.waitForExistence(timeout: Self.shortTimeout)
            || modelsSidebarItemByTitle.waitForExistence(timeout: Self.shortTimeout)
    }

    @MainActor
    private func createSessionAndWaitForDetail(app: XCUIApplication) -> Bool {
        if waitForSessionDetailReady(app: app, timeout: Self.shortTimeout) {
            return true
        }

        for _ in 0..<3 {
            clickButton("sessions.toolbar.new", app: app)
            if waitForSessionDetailReady(app: app, timeout: Self.longTimeout) {
                return true
            }

            let newSessionTitle = app.staticTexts["New Session"].firstMatch
            if newSessionTitle.waitForExistence(timeout: Self.shortTimeout) {
                newSessionTitle.click()
                if waitForSessionDetailReady(app: app, timeout: Self.mediumTimeout) {
                    return true
                }
            }
        }

        return waitForSessionDetailReady(app: app, timeout: Self.mediumTimeout)
    }

    @MainActor
    private func clickButton(_ identifier: String, app: XCUIApplication) {
        let toolbarCandidates = app.toolbars.buttons.matching(identifier: identifier)
        let toolbarElements = toolbarCandidates.allElementsBoundByIndex
        if let hittableToolbarButton = toolbarElements.first(where: { $0.exists && $0.isHittable }) {
            hittableToolbarButton.click()
            return
        }
        if let toolbarButton = toolbarElements.first(where: { $0.exists }) {
            toolbarButton.click()
            return
        }

        let candidates = app.descendants(matching: .button).matching(identifier: identifier)
        let firstCandidate = candidates.firstMatch
        XCTAssertTrue(firstCandidate.waitForExistence(timeout: Self.mediumTimeout), "Missing button: \(identifier)")
        let hittableCandidate = candidates.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable })
        (hittableCandidate ?? firstCandidate).click()
    }

    @MainActor
    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForSessionDetailReady(app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let detailMarker = element("sessions.detail", app: app)
        let messageField = element("session.detail.messageField", app: app)
        let renameButton = button("sessions.toolbar.rename", app: app)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if detailMarker.exists || messageField.exists {
                return true
            }
            if renameButton.exists && renameButton.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return detailMarker.exists || messageField.exists || (renameButton.exists && renameButton.isEnabled)
    }

}
