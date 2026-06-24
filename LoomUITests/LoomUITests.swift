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

    func testNoModelGuidanceOpensModelsRecovery() throws {
        let app = launchApp()
        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        typeMessage("Help me get set up", app: app)

        clickButton("session.detail.sendButton", app: app)

        XCTAssertTrue(app.staticTexts["Choose a model to chat with."].waitForExistence(timeout: Self.mediumTimeout))

        clickButton("session.banner.action", app: app)

        XCTAssertTrue(element("root.detail.models", app: app).waitForExistence(timeout: Self.mediumTimeout))
        XCTAssertTrue(app.staticTexts["ui-test-model"].waitForExistence(timeout: Self.mediumTimeout))
        XCTAssertTrue(app.buttons["Set Active"].firstMatch.waitForExistence(timeout: Self.mediumTimeout))
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

    func testReturnKeySendsMessageFromComposer() throws {
        let app = launchApp(
            activeModelTag: "ui-test-model",
            chatScenario: .streamSuccess
        )
        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        let messageField = element("session.detail.messageField", app: app)
        XCTAssertTrue(messageField.waitForExistence(timeout: Self.mediumTimeout))
        XCTAssertLessThanOrEqual(messageField.frame.height, 70, "Expected the empty composer to stay compact.")
        messageField.click()
        messageField.typeText("return-key-send")
        XCTAssertLessThanOrEqual(messageField.frame.height, 70, "Expected single-line composer text to stay compact.")
        messageField.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            waitForAssistantBubbleContaining(
                "Hello from stub response",
                app: app,
                timeout: Self.longTimeout
            ),
            "Expected Return to submit the composer without leaving the chat."
        )
        XCTAssertTrue(messageField.exists, "Expected the composer to remain available after sending.")
        XCTAssertLessThanOrEqual(messageField.frame.height, 70, "Expected the composer to remain compact after sending.")
    }

    func testLongModelLabelKeepsSendButtonHittable() throws {
        let app = launchApp(
            activeModelTag: "llama-3.2-ultra-long-model-name-for-ui-layout-verification-1234567890",
            chatScenario: .streamSuccess
        )
        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        typeMessage("layout-check", app: app)

        let sendButton = button("session.detail.sendButton", app: app)
        XCTAssertTrue(waitForEnabled(sendButton, timeout: Self.mediumTimeout))
        XCTAssertTrue(sendButton.isHittable)
    }

    func testStopGenerationKeepsAppUsableAfterRelaunch() throws {
        let app = launchApp(
            activeModelTag: "ui-test-model",
            chatScenario: .cancelablePartial
        )
        XCTAssertTrue(createSessionAndWaitForDetail(app: app))

        typeMessage("cancel-me", app: app)

        clickButton("session.detail.sendButton", app: app)

        let stopButton = button("session.detail.stopButton", app: app)
        XCTAssertTrue(
            waitForAssistantBubbleContaining("partial", app: app, timeout: Self.longTimeout),
            "Expected partial assistant content before stopping."
        )
        XCTAssertTrue(stopButton.waitForExistence(timeout: Self.mediumTimeout), "Expected stop button to remain available.")

        clickButton("session.detail.stopButton", app: app)
        _ = waitForNotExists(stopButton, timeout: Self.mediumTimeout)

        app.terminate()

        let relaunched = launchApp(
            resetStorage: false,
            activeModelTag: "ui-test-model",
            chatScenario: .cancelablePartial
        )
        XCTAssertTrue(createSessionAndWaitForDetail(app: relaunched))
        XCTAssertTrue(
            waitForAssistantBubbleContaining("partial", app: relaunched, timeout: Self.longTimeout),
            "Expected canceled partial assistant content to survive relaunch."
        )
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

    private func createSessionAndWaitForDetail(app: XCUIApplication) -> Bool {
        if waitForSessionDetailReady(app: app, timeout: Self.shortTimeout) {
            return true
        }

        for _ in 0..<3 {
            clickButton("sessions.toolbar.new", app: app)
            if waitForSessionDetailReady(app: app, timeout: Self.longTimeout) {
                return true
            }

            let newSessionTitle = app.staticTexts["New Chat"].firstMatch
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
        let deadline = Date().addingTimeInterval(Self.mediumTimeout)

        while Date() < deadline {
            let toolbarCandidates = app.toolbars.buttons.matching(identifier: identifier)
            if let toolbarButton = toolbarCandidates.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                toolbarButton.click()
                return
            }

            let candidates = app.descendants(matching: .button).matching(identifier: identifier)
            if let candidate = candidates.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                candidate.click()
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let firstCandidate = app.descendants(matching: .button)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertTrue(firstCandidate.waitForExistence(timeout: Self.shortTimeout), "Missing button: \(identifier)")
        XCTAssertTrue(firstCandidate.isHittable, "Button exists but is not hittable: \(identifier)")
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
        let bubble = element("session.message.assistant.bubble", app: app)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if bubble.exists && bubble.label.localizedCaseInsensitiveContains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return bubble.exists && bubble.label.localizedCaseInsensitiveContains(text)
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
