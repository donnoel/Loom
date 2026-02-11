//
//  LoomUITestsLaunchTests.swift
//  LoomUITests
//
//  Created by Don Noel on 1/27/26.
//

import Foundation
import XCTest

final class LoomUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let testRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LoomUITestsLaunch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRootURL) }

        let app = XCUIApplication()
        app.launchEnvironment["LOOM_APP_SUPPORT_ROOT"] = testRootURL.path
        app.launchEnvironment["LOOM_UI_TEST_RESET_DEFAULTS"] = "1"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
