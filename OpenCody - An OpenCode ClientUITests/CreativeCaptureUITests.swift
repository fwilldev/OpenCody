import XCTest

/// Captures real screens for the App Store creative assets (see AppStoreScreenshots/README.md).
///
/// Expects a live OpenCode server whose project already has the two demo sessions named in
/// `OPENCODY_CAPTURE_SESSIONS` (comma-separated titles; the second one with a pending
/// permission request). Skipped unless `OPENCODY_CAPTURE_HOST`, `OPENCODY_CAPTURE_PORT`,
/// `OPENCODY_CAPTURE_PASSWORD`, `OPENCODY_CAPTURE_PROJECT` and `OPENCODY_CAPTURE_SESSIONS`
/// are set — pass them with the `TEST_RUNNER_` prefix. The added server is deleted again at the end.
final class CreativeCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func env(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
            throw XCTSkip("\(key) not set")
        }
        return value
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "field \(field)")
        field.tap()
        field.typeText(text)
    }

    private func dismissPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Continue", "Not Now", "Maybe later", "Maybe Later", "Not now"] {
            for root in [app!, springboard] {
                let button = root.buttons[label].firstMatch
                if button.waitForExistence(timeout: 1), button.isHittable { button.tap() }
            }
        }
    }

    private func tapTab(_ name: String) {
        let tab = app.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "tab \(name)")
        for _ in 0..<5 where tab.isHittable == false { sleep(1) }
        tab.tap()
    }

    private func deleteServer(named name: String) {
        let row = app.staticTexts[name].firstMatch
        guard row.waitForExistence(timeout: 2) else { return }
        row.tap()
        let delete = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
        if !delete.waitForExistence(timeout: 3) || !delete.isHittable { app.swipeUp() }
        delete.tap()
        let confirm = app.buttons["Delete"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        _ = app.staticTexts[name].waitForNonExistence(timeout: 5)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    func testCaptureCreativeScreens() throws {
        let host = try env("OPENCODY_CAPTURE_HOST")
        let port = try env("OPENCODY_CAPTURE_PORT")
        let password = try env("OPENCODY_CAPTURE_PASSWORD")
        let project = try env("OPENCODY_CAPTURE_PROJECT")
        let sessions = try env("OPENCODY_CAPTURE_SESSIONS").split(separator: ",").map(String.init)
        let serverName = "My Mac"

        app = XCUIApplication()
        app.launch()

        dismissPrompts()
        tapTab("Settings")
        let servers = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Servers'")).firstMatch
        XCTAssertTrue(servers.waitForExistence(timeout: 5))
        servers.tap()
        while app.staticTexts[serverName].waitForExistence(timeout: 2) { deleteServer(named: serverName) }
        app.navigationBars["Servers"].buttons["Add"].firstMatch.tap()

        type(serverName, into: app.textFields["server.name"])
        type(host, into: app.textFields["server.host"])
        type(port, into: app.textFields["server.port"])
        type("opencode", into: app.textFields["server.username"])
        type(password, into: app.secureTextFields["server.password"])
        let test = app.buttons["Test Connection"]
        if !test.isHittable { app.swipeUp() }
        test.tap()
        XCTAssertTrue(app.staticTexts["Connection successful"].waitForExistence(timeout: 15), "test connection")
        app.buttons["Save Server"].tap()

        // The system "save password" sheet can appear several seconds after saving.
        let projectCell = app.staticTexts[project].firstMatch
        for _ in 0..<4 where !projectCell.isHittable {
            dismissPrompts()
            tapTab("Dashboard")
            dismissPrompts()
            _ = projectCell.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(projectCell.waitForExistence(timeout: 10), "project on dashboard")
        sleep(2)
        screenshot("dashboard")
        projectCell.tap()

        let first = app.staticTexts[sessions[0]].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "session \(sessions[0])")
        sleep(2)
        screenshot("sessions")

        // Finished session: reply, tool calls, diff and todos.
        first.tap()
        sleep(6)
        screenshot("chat-end")
        app.swipeDown()
        sleep(2)
        screenshot("chat-mid")
        app.swipeDown()
        app.swipeDown()
        sleep(2)
        screenshot("chat-top")
        // The actions menu label is the short session id above an ellipsis.
        let menu = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ses_' OR label CONTAINS[c] 'More' OR label == 'Session Actions'")).firstMatch
        if menu.waitForExistence(timeout: 3) {
            menu.tap()
            let diff = app.buttons["View Diff"].firstMatch
            if diff.waitForExistence(timeout: 3) {
                diff.tap()
                sleep(4)
                screenshot("diff")
                app.swipeDown(velocity: .fast)
                sleep(2)
            }
            menu.tap()
            let todos = app.buttons["Todos"].firstMatch
            if todos.waitForExistence(timeout: 3) {
                todos.tap()
                sleep(3)
                screenshot("todos")
                app.swipeDown(velocity: .fast)
                sleep(2)
            }
        }
        back()

        // Session waiting on an edit permission.
        if sessions.count > 1 {
            let second = app.staticTexts[sessions[1]].firstMatch
            if second.waitForExistence(timeout: 5) {
                second.tap()
                sleep(6)
                screenshot("permission")
                back()
            }
        }

        for _ in 0..<3 where !app.buttons["Settings"].firstMatch.isHittable { back() }
        tapTab("Settings")
        if servers.waitForExistence(timeout: 3) { servers.tap() }
        deleteServer(named: serverName)
    }
}
