import XCTest

/// Drives the real UI against a live OpenCode 2.x server: add the server with the
/// 2.x setting, open its project, start a session and chat.
///
/// Skipped unless `OPENCODY_V2_URL_HOST`, `OPENCODY_V2_PORT`, `OPENCODY_V2_PASSWORD` and
/// `OPENCODY_V2_PROJECT` (the project folder name) are set — pass them with the
/// `TEST_RUNNER_` prefix. The added server is deleted again at the end.
final class V2ServerUITests: XCTestCase {
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

    /// Dismiss system and in-app prompts (password saving, rating, tips) that cover the UI.
    private func dismissPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Continue", "Später", "Not Now", "Nicht jetzt", "Maybe later", "Maybe Later", "Not now"] {
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

    /// Remove the test server if a previous run left it behind (on the Servers screen).
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAddV2ServerAndChat() throws {
        let host = try env("OPENCODY_V2_URL_HOST")
        let port = try env("OPENCODY_V2_PORT")
        let password = try env("OPENCODY_V2_PASSWORD")
        let project = try env("OPENCODY_V2_PROJECT")
        let serverName = "V2 UITest"

        app = XCUIApplication()
        app.launch()

        // Settings → Servers → +
        dismissPrompts()
        tapTab("Settings")
        let servers = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Servers'")).firstMatch
        XCTAssertTrue(servers.waitForExistence(timeout: 5))
        servers.tap()
        while app.staticTexts[serverName].waitForExistence(timeout: 2) { deleteServer(named: serverName) }
        app.navigationBars["Servers"].buttons["Add"].firstMatch.tap()

        // Fill the form, choosing OpenCode 2.x.
        type(serverName, into: app.textFields["My Server"])
        type(host, into: app.textFields["192.168.1.100"])
        type(port, into: app.textFields["Default"])
        app.buttons["OpenCode 2.x"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'opencode'")).firstMatch.exists)
        type("opencode", into: app.textFields["admin"])
        type(password, into: app.secureTextFields["Password"])
        screenshot("form")

        let test = app.buttons["Test Connection"]
        if !test.isHittable { app.swipeUp() }
        test.tap()
        XCTAssertTrue(app.staticTexts["Connection successful"].waitForExistence(timeout: 15), "test connection")
        app.buttons["Save Server"].tap()

        // Dashboard lists the server's project.
        // The system "save password" sheet can appear several seconds after saving.
        let projectCell = app.staticTexts[project].firstMatch
        for _ in 0..<4 where !projectCell.isHittable {
            dismissPrompts()
            tapTab("Dashboard")
            dismissPrompts()
            _ = projectCell.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(projectCell.waitForExistence(timeout: 10), "project on dashboard")
        screenshot("dashboard")
        dismissPrompts()
        projectCell.tap()

        // New session → chat.
        app.navigationBars.buttons["Add"].firstMatch.tap()
        screenshot("create-session")
        let create = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Create' OR label CONTAINS[c] 'Start'")).firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        let input = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15), "chat input")
        input.tap()
        input.typeText("Reply with exactly the word: pineapple")
        screenshot("typed")
        // Icon-only button; its label is the localized SF Symbol name.
        let send = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'Send' OR label CONTAINS[c] 'up' OR label CONTAINS[c] 'oben' OR identifier == 'arrow.up.circle.fill'"
        )).firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        let reply = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'pineapple'"))
        let deadline = Date().addingTimeInterval(120)
        // The prompt itself contains the word; wait for a second occurrence (the reply).
        while reply.count < 2, Date() < deadline { sleep(1) }
        screenshot("reply")
        XCTAssertGreaterThanOrEqual(reply.count, 2, "assistant reply rendered")

        // Clean up the server entry: back out of the chat and project first — the
        // tab bar is hidden while a chat is open.
        for _ in 0..<3 where !app.buttons["Settings"].firstMatch.isHittable {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }
        tapTab("Settings")
        if app.buttons.containing(NSPredicate(format: "label CONTAINS 'Servers'")).firstMatch.waitForExistence(timeout: 3) {
            app.buttons.containing(NSPredicate(format: "label CONTAINS 'Servers'")).firstMatch.tap()
        }
        deleteServer(named: serverName)
    }
}
