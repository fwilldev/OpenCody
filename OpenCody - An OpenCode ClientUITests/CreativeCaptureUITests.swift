import XCTest

/// Captures real screens for the App Store screenshots and creative assets
/// (see OpenCody-AppStore/README.md, outside this repo).
///
/// Expects a live OpenCode server whose project already has the sessions named in
/// `OPENCODY_CAPTURE_SESSIONS` (comma-separated titles). The first one also gets its
/// diff, todos and files captured. Skipped unless `OPENCODY_CAPTURE_HOST`,
/// `OPENCODY_CAPTURE_PORT`, `OPENCODY_CAPTURE_PASSWORD`, `OPENCODY_CAPTURE_PROJECT`
/// (folder name) and `OPENCODY_CAPTURE_SESSIONS` are set — pass them with the
/// `TEST_RUNNER_` prefix. Optional: `OPENCODY_CAPTURE_PAIRING` (a fresh 2.x pairing
/// link, used instead of host and password), `OPENCODY_CAPTURE_PROJECT_NAME` (renames
/// the project from its context menu), `OPENCODY_CAPTURE_SERVER_NAME`.
/// The added server is deleted again at the end in the compact layout. The regular
/// (sidebar) layout expects a fresh install without servers. `OPENCODY_CAPTURE_LANDSCAPE=1`
/// rotates first (the 1.8 iPad set).
final class CreativeCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    /// Sidebar layout (iPad, iPhone Duo's inner display), decided by the window, not the device.
    private var isRegular: Bool { app.navigationBars["OpenCody"].exists }
    /// Files, Todos and Diff sit in a panel beside the chat when the detail column is wide enough.
    private var hasUtilitiesPanel: Bool { app.buttons["Utilities"].firstMatch.exists }

    override func setUp() {
        continueAfterFailure = false
    }

    private func env(_ key: String) throws -> String {
        guard let value = optionalEnv(key) else { throw XCTSkip("\(key) not set") }
        return value
    }

    private func optionalEnv(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { return nil }
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

    private func openServers() {
        let servers = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Servers' AND NOT (label CONTAINS 'Manage')")).firstMatch
        for _ in 0..<3 where !app.buttons["Settings"].firstMatch.isHittable { back() }
        tapTab("Settings")
        // The Settings tab remembers an earlier push to Servers.
        if app.navigationBars["Servers"].waitForExistence(timeout: 2) { return }
        XCTAssertTrue(servers.waitForExistence(timeout: 5))
        servers.tap()
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
        // On iPad the first bar button can be the sidebar toggle.
        let button = app.navigationBars.buttons["BackButton"].firstMatch
        (button.exists ? button : app.navigationBars.buttons.element(boundBy: 0)).tap()
        sleep(1)
    }

    /// Long-press `element`, capture its context menu, then pick `action`.
    private func contextMenu(on element: XCUIElement, capture name: String, action: String) {
        element.press(forDuration: 1.2)
        let item = app.buttons[action].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(action) in context menu")
        sleep(1)
        screenshot(name)
        item.tap()
    }

    /// Replace the text of the rename alert's field with `name` and save.
    private func renameInAlert(to name: String, capture: String? = nil) {
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 60) + name)
        // A tap sent while the keyboard is still settling after typeText is dropped.
        sleep(2)
        if let capture { screenshot(capture) }
        app.alerts.buttons["Save"].tap()
    }

    private func addServer(named serverName: String) throws {
        if isRegular {
            app.buttons["Add Server"].firstMatch.tap()
        } else {
            app.navigationBars["Servers"].buttons["Add"].firstMatch.tap()
        }
        // Return ends editing, so the keyboard is gone for the form capture.
        type(serverName + "\n", into: app.textFields["server.name"])
        if let pairing = optionalEnv("OPENCODY_CAPTURE_PAIRING") {
            type(pairing + "\n", into: app.textFields["server.pairingLink"])
            let paired = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Paired'")).firstMatch
            XCTAssertTrue(paired.waitForExistence(timeout: 15), "pairing")
        } else {
            // Sign-in first: below the address, these hide behind the keyboard on iPad.
            type("opencode\n", into: app.textFields["server.username"])
            type(try env("OPENCODY_CAPTURE_PASSWORD") + "\n", into: app.secureTextFields["server.password"])
            type(try env("OPENCODY_CAPTURE_HOST"), into: app.textFields["server.host"])
            type(try env("OPENCODY_CAPTURE_PORT"), into: app.textFields["server.port"])
            let hide = app.keyboards.buttons["Hide keyboard"].firstMatch
            if hide.exists { hide.tap() }
        }
        let detected = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Detected'")).firstMatch
        _ = detected.waitForExistence(timeout: 10)
        let test = app.buttons["Test Connection"]
        if !test.isHittable { app.swipeUp() }
        test.tap()
        XCTAssertTrue(app.staticTexts["Connection successful"].waitForExistence(timeout: 15), "test connection")
        let top = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Paired' OR label == 'Name'")).firstMatch
        if !top.isHittable { app.collectionViews.firstMatch.swipeDown() }
        sleep(2)
        screenshot("server-form")
        app.buttons["Save Server"].tap()
    }

    /// The chat of the first session also gets its diff, files and todos captured.
    private func captureUtilities() {
        if hasUtilitiesPanel {
            app.buttons["Utilities"].firstMatch.tap()
            sleep(4)
            screenshot("files")
            let src = app.staticTexts["src"].firstMatch
            if src.waitForExistence(timeout: 3) {
                src.tap()
                sleep(3)
                screenshot("files-src")
            }
            for (tab, name) in [("Diff", "diff"), ("Todos", "todos")] {
                app.buttons[tab].firstMatch.tap()
                sleep(4)
                screenshot(name)
            }
            app.buttons["Utilities"].firstMatch.tap()
            sleep(1)
            return
        }
        let menu = app.buttons["Session Actions"].firstMatch
        for (item, name) in [("View Diff", "diff"), ("Todos", "todos"), ("File Explorer", "files")] {
            XCTAssertTrue(menu.waitForExistence(timeout: 5), "session actions")
            menu.tap()
            let button = app.buttons[item].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3), item)
            button.tap()
            sleep(2)
            // Tapping the grabber moves a half-height sheet to full height.
            let grabber = app.buttons["Sheet Grabber"].firstMatch
            if grabber.exists, "\(grabber.value ?? "")".contains("Half") { grabber.tap() }
            sleep(2)
            screenshot(name)
            if name == "files" {
                let src = app.staticTexts["src"].firstMatch
                if src.waitForExistence(timeout: 3) {
                    src.tap()
                    sleep(3)
                    screenshot("files-src")
                }
            }
            app.buttons["Close"].firstMatch.tap()
            sleep(2)
        }
    }

    func testCaptureCreativeScreens() throws {
        _ = try env("OPENCODY_CAPTURE_HOST")
        let project = try env("OPENCODY_CAPTURE_PROJECT")
        let sessions = try env("OPENCODY_CAPTURE_SESSIONS").split(separator: ",").map(String.init)
        let projectName = optionalEnv("OPENCODY_CAPTURE_PROJECT_NAME")
        let serverName = optionalEnv("OPENCODY_CAPTURE_SERVER_NAME") ?? "Mac Studio"

        if optionalEnv("OPENCODY_CAPTURE_LANDSCAPE") != nil { XCUIDevice.shared.orientation = .landscapeLeft }
        app = XCUIApplication()
        app.launch()

        // What's New shows up a few seconds after a fresh install.
        let whatsNew = app.buttons["Continue"].firstMatch
        if whatsNew.waitForExistence(timeout: 8) { whatsNew.tap() }
        dismissPrompts()
        if !isRegular {
            openServers()
            while app.staticTexts[serverName].waitForExistence(timeout: 2) { deleteServer(named: serverName) }
        }
        try addServer(named: serverName)
        // The server switcher keeps showing "connecting" for a server added in this launch.
        sleep(3)
        app.terminate()
        app.launch()
        sleep(5)

        // The project may still carry the custom name of an earlier run.
        let names = [project, projectName].compactMap { $0 }
        let projectCell = app.staticTexts.matching(NSPredicate(format: "label IN %@", names)).firstMatch
        // The system "save password" sheet can appear several seconds after saving.
        for _ in 0..<4 where !projectCell.isHittable {
            dismissPrompts()
            if !isRegular { tapTab("Dashboard") }
            dismissPrompts()
            _ = projectCell.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(projectCell.waitForExistence(timeout: 10), "project listed")
        sleep(2)
        if let projectName {
            contextMenu(on: projectCell, capture: "project-menu", action: "Rename Project")
            renameInAlert(to: projectName, capture: "project-rename")
            XCTAssertTrue(app.staticTexts[projectName].waitForExistence(timeout: 10), "renamed project")
            sleep(2)
        }
        screenshot("dashboard")
        app.staticTexts[projectName ?? project].firstMatch.tap()

        let first = app.staticTexts[sessions[0]].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "session \(sessions[0])")
        sleep(2)
        screenshot("sessions")
        if projectName != nil {
            contextMenu(on: first, capture: "session-menu", action: "Rename Session")
            sleep(2)
            screenshot("session-rename")
            app.alerts.buttons["Cancel"].tap()
            sleep(1)
        }

        for (index, title) in sessions.enumerated() {
            let row = app.staticTexts[title].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "session \(title)")
            row.tap()
            sleep(6)
            screenshot("chat-\(index)")
            if hasUtilitiesPanel, index > 0 {
                app.buttons["Utilities"].firstMatch.tap()
                sleep(4)
                screenshot("chat-\(index)-panel")
                app.buttons["Utilities"].firstMatch.tap()
            }
            if index == 0 { captureUtilities() }
            back()
        }

        // The sidebar's Settings button ignores synthesized taps: start regular-width
        // runs from a fresh install instead of cleaning up.
        guard !isRegular else { return }
        back()
        sleep(3)
        screenshot("dashboard-end")
        openServers()
        sleep(2)
        screenshot("servers")
        let row = app.staticTexts[serverName].firstMatch
        if optionalEnv("OPENCODY_CAPTURE_PAIRING") != nil, row.exists {
            contextMenu(on: row, capture: "server-menu", action: "Pair a Device")
            sleep(3)
            screenshot("pair-device")
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }
        deleteServer(named: serverName)
    }
}
