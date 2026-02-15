import Foundation
import XCTest

final class LoomUITests: XCTestCase {
    private enum ChatScenario: String {
        case streamSuccess = "stream_success"
        case cancelablePartial = "cancelable_partial"
    }

    private static let shortTimeout: TimeInterval = 2
    private static let mediumTimeout: TimeInterval = 5
    private static let longTimeout: TimeInterval = 12

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSidebarNavigationShowsCoreScreens() throws {
        let app = launchApp()
        XCTAssertTrue(createSessionAndWaitForDetail(app: app))
        XCTAssertTrue(element("root.detail.sessions", app: app).waitForExistence(timeout: Self.mediumTimeout))

        tapSidebarItem(identifier: "sidebar.models", title: "Models", app: app)
        XCTAssertTrue(element("root.detail.models", app: app).waitForExistence(timeout: Self.mediumTimeout))

        tapSidebarItem(identifier: "sidebar.settings", title: "Settings", app: app)
        XCTAssertTrue(element("root.detail.settings", app: app).waitForExistence(timeout: Self.mediumTimeout))
    }

    func testCreateAndDeleteSessionFromToolbar() throws {
        let app = launchApp()

        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        let deleteButton = button("sessions.toolbar.delete", app: app)
        XCTAssertTrue(waitForEnabled(deleteButton, timeout: Self.mediumTimeout))
        deleteButton.click()
    }

    func testSendWithoutModelShowsSetupGuidance() throws {
        let app = launchApp()
        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        typeMessage("Hello from UI test", app: app)

        clickButton("session.detail.sendButton", app: app)

        XCTAssertTrue(app.staticTexts["Choose a model to chat with."].waitForExistence(timeout: Self.mediumTimeout))
    }

    func testSendStreamsAssistantReply() throws {
        let app = launchApp(
            activeModelTag: "ui-test-model",
            chatScenario: .streamSuccess
        )
        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        typeMessage("stream-happy-path", app: app)

        clickButton("session.detail.sendButton", app: app)

        let typingState = element("session.message.assistant.typing", app: app)
        let stopButton = button("session.detail.stopButton", app: app)
        let sawStreamingState = stopButton.waitForExistence(timeout: Self.shortTimeout)
            || typingState.waitForExistence(timeout: Self.shortTimeout)

        if sawStreamingState {
            XCTAssertTrue(waitForNotExists(stopButton, timeout: Self.longTimeout))
            XCTAssertTrue(waitForNotExists(typingState, timeout: Self.longTimeout))
        }

        XCTAssertTrue(
            waitForAssistantBubbleContaining(
                "Hello from stub response",
                app: app,
                timeout: Self.longTimeout
            ),
            "Expected completed assistant bubble content."
        )
    }

    func testStopGenerationKeepsPartialReplyAfterRelaunch() throws {
        let app = launchApp(
            activeModelTag: "ui-test-model",
            chatScenario: .cancelablePartial
        )
        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        typeMessage("cancel-me", app: app)

        clickButton("session.detail.sendButton", app: app)

        let typingState = element("session.message.assistant.typing", app: app)
        let stopButton = button("session.detail.stopButton", app: app)
        let sawStreamingState = stopButton.waitForExistence(timeout: Self.longTimeout)
            || typingState.waitForExistence(timeout: Self.longTimeout)
        XCTAssertTrue(sawStreamingState, "Expected assistant streaming state to appear.")

        XCTAssertTrue(
            waitForAssistantBubbleContaining("partial", app: app, timeout: Self.longTimeout),
            "Expected partial assistant content before cancel."
        )

        stopButton.click()
        XCTAssertTrue(waitForNotExists(stopButton, timeout: Self.mediumTimeout))
        XCTAssertTrue(waitForNotExists(typingState, timeout: Self.mediumTimeout))
        XCTAssertTrue(waitForAssistantBubbleContaining("partial", app: app, timeout: Self.mediumTimeout))

        app.terminate()

        let relaunched = launchApp(
            resetStorage: false,
            activeModelTag: "ui-test-model",
            chatScenario: .cancelablePartial
        )
        XCTAssertTrue(waitForAssistantBubbleContaining("partial", app: relaunched, timeout: Self.longTimeout))
    }

    private func launchApp(
        resetStorage: Bool = true,
        activeModelTag: String? = nil,
        chatScenario: ChatScenario? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LOOM_UI_TEST_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["LOOM_UI_TEST_RESET_STORAGE"] = resetStorage ? "1" : "0"
        if let activeModelTag {
            app.launchEnvironment["LOOM_UI_TEST_ACTIVE_MODEL_TAG"] = activeModelTag
        }
        if let chatScenario {
            app.launchEnvironment["LOOM_UI_TEST_CHAT_STUB_SCENARIO"] = chatScenario.rawValue
        }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Self.mediumTimeout))
        return app
    }

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

    private func button(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .button)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func element(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func ensureSidebarVisible(app: XCUIApplication) {
        let modelsSidebarItemByTitle = app.outlines.staticTexts["Models"].firstMatch
        if modelsSidebarItemByTitle.waitForExistence(timeout: 1) {
            return
        }

        app.typeKey("s", modifierFlags: [.command, .option])
        _ = modelsSidebarItemByTitle.waitForExistence(timeout: Self.shortTimeout)
    }

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

    private func typeMessage(_ text: String, app: XCUIApplication) {
        let messageField = element("session.detail.messageField", app: app)
        XCTAssertTrue(messageField.waitForExistence(timeout: Self.mediumTimeout))

        let sendButton = button("session.detail.sendButton", app: app)
        for _ in 0..<3 {
            messageField.click()
            messageField.typeKey("a", modifierFlags: .command)
            messageField.typeText(text)

            if waitForEnabled(sendButton, timeout: Self.shortTimeout) {
                return
            }
        }

        XCTFail("Message entry did not enable send button.")
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNotExists(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForAssistantBubbleContaining(
        _ text: String,
        app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let bubbleQuery = app.descendants(matching: .any)
            .matching(identifier: "session.message.assistant.bubble")
            .containing(NSPredicate(format: "label CONTAINS[c] %@", text))
        return bubbleQuery.firstMatch.waitForExistence(timeout: timeout)
    }

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
