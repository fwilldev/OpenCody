import XCTest

/// The two layouts against a live server: sidebar plus chat in a regular-width window
/// (iPhone Duo's inner display, iPad), and a compact ↔ regular switch keeping the chat.
///
/// Skipped unless `OPENCODY_LAYOUT_HOST`, `OPENCODY_LAYOUT_PORT`, `OPENCODY_LAYOUT_PASSWORD`,
/// `OPENCODY_LAYOUT_PROJECT` (project name as listed) and `OPENCODY_LAYOUT_SESSION` (title of an
/// existing session) are set — pass them with the `TEST_RUNNER_` prefix. The test server
/// stays saved, so the app must be freshly installed or have no other server.
final class AdaptiveLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func env(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else {
            throw XCTSkip("\(key) not set")
        }
        return value
    }

    private func dismissPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Continue", "Not Now", "Maybe later", "Don’t Allow", "Allow", "Later"] {
            for root in [app!, springboard] {
                let button = root.buttons[label].firstMatch
                if button.waitForExistence(timeout: 1), button.isHittable { button.tap() }
            }
        }
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The regular layout titles its sidebar "OpenCody"; the compact one has a tab bar instead.
    private var isRegularLayout: Bool {
        app.navigationBars["OpenCody"].waitForExistence(timeout: 3)
    }

    private var chatInput: XCUIElement { app.textViews.firstMatch }

    /// Launches the app, adding the test server first on a fresh install.
    private func launchConnected() throws -> (project: String, session: String) {
        let host = try env("OPENCODY_LAYOUT_HOST")
        let port = try env("OPENCODY_LAYOUT_PORT")
        let password = try env("OPENCODY_LAYOUT_PASSWORD")
        let project = try env("OPENCODY_LAYOUT_PROJECT")
        let session = try env("OPENCODY_LAYOUT_SESSION")

        app = XCUIApplication()
        app.launch()
        dismissPrompts()

        let addServer = app.buttons["Add Server"].firstMatch
        if addServer.waitForExistence(timeout: 3) {
            addServer.tap()
            for (text, field) in [
                ("Layout Test\n", app.textFields["server.name"]),
                ("opencode\n", app.textFields["server.username"]),
                (password + "\n", app.secureTextFields["server.password"]),
                (host, app.textFields["server.host"]),
                (port, app.textFields["server.port"]),
            ] {
                XCTAssertTrue(field.waitForExistence(timeout: 5), "field \(field)")
                field.tap()
                field.typeText(text)
            }
            let test = app.buttons["Test Connection"]
            if !test.isHittable { app.swipeUp() }
            test.tap()
            XCTAssertTrue(app.staticTexts["Connection successful"].waitForExistence(timeout: 15), "test connection")
            // Offscreen form rows aren't in the hierarchy until scrolled to.
            let save = app.buttons["Save Server"]
            for _ in 0..<4 where !(save.exists && save.isHittable) { app.swipeUp() }
            save.tap()
            dismissPrompts()
        }
        XCTAssertTrue(app.staticTexts[project].firstMatch.waitForExistence(timeout: 20), "project listed")
        return (project, session)
    }

    private func openChat(project: String, session: String) {
        app.staticTexts[project].firstMatch.tap()
        let row = app.staticTexts[session].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "session listed")
        row.tap()
        XCTAssertTrue(chatInput.waitForExistence(timeout: 15), "chat input")
    }

    /// iPhone Duo's inner display (and iPad): projects in the sidebar, the chat beside it.
    func testRegularWidthShowsSidebarAndChat() throws {
        let (project, session) = try launchConnected()
        if !isRegularLayout {
            // Large iPhones are regular width in landscape; the Duo's outer display is not.
            XCUIDevice.shared.orientation = .landscapeLeft
            guard isRegularLayout else {
                throw XCTSkip("Compact window. On iPhone Duo, unfold to the inner display in Device Hub first.")
            }
        }
        openChat(project: project, session: session)

        XCTAssertTrue(app.staticTexts[project].firstMatch.isHittable, "sidebar visible next to the chat")
        XCTAssertTrue(chatInput.isHittable, "composer visible next to the sidebar")
        XCTAssertTrue(app.staticTexts[session].firstMatch.exists, "chat title")
        screenshot("sidebar-and-chat")
    }

    /// A fold or Split View resize swaps the compact and regular layouts; rotating a large
    /// iPhone does the same, so it stands in for the fold here.
    func testSizeClassChangeKeepsChatAndDraft() throws {
        let (project, session) = try launchConnected()
        guard !isRegularLayout else { throw XCTSkip("Needs a compact window that turns regular in landscape.") }
        openChat(project: project, session: session)
        let draft = "Draft that survives the resize"
        chatInput.tap()
        chatInput.typeText(draft)

        XCUIDevice.shared.orientation = .landscapeLeft
        guard isRegularLayout else { throw XCTSkip("Stays compact in landscape on this device.") }
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "chat still open after the resize")
        XCTAssertEqual(chatInput.value as? String, draft)
        XCTAssertTrue(app.staticTexts[project].firstMatch.isHittable, "project selected in the sidebar")
        screenshot("regular")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "chat still open after resizing back")
        XCTAssertEqual(chatInput.value as? String, draft)
        screenshot("compact")
    }
}
