import XCTest
@testable import OpenCody___An_OpenCode_Client

/// State that has to survive a size class change (Split View resize, folding iPhone Duo),
/// when the compact and regular layouts swap.
@MainActor
final class ResizeStateTests: XCTestCase {

    private func session(_ id: String, directory: String = "/repo") throws -> Session {
        let json = """
        {"id":"\(id)","projectID":"p","directory":"\(directory)","title":"T","version":"1",
         "time":{"created":1,"updated":1}}
        """
        return try JSONDecoder().decode(Session.self, from: Data(json.utf8))
    }

    func testOpenChatIsVisibleToBothLayouts() throws {
        let router = AppRouter()
        let chat = try session("ses_1")
        router.openChat(chat)

        // Compact pushes the whole path, regular selects the project and stacks the rest.
        XCTAssertEqual(router.dashboardPath, [.project("/repo"), .chat(chat)])
        XCTAssertEqual(router.selectedProject, "/repo")
        XCTAssertEqual(router.selectedSession, "ses_1")
    }

    func testReselectingTheSameProjectKeepsTheChat() throws {
        let router = AppRouter()
        router.openChat(try session("ses_1"))
        router.navigateToSettings()

        router.selectProject("/repo")
        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertEqual(router.selectedSession, "ses_1")

        router.selectProject("/other")
        XCTAssertEqual(router.dashboardPath, [.project("/other")])
        XCTAssertNil(router.selectedSession)

        router.selectProject(nil)
        XCTAssertTrue(router.dashboardPath.isEmpty)
    }

    func testChatModelIsReusedWithItsDraft() throws {
        let manager = ConnectionManager()
        let chat = try session("ses_draft")
        let first = ChatViewModel.shared(session: chat, connectionManager: manager)
        first.draftText = "half-written"
        first.isUtilityOpen = true

        let rebuilt = ChatViewModel.shared(session: chat, connectionManager: manager)
        XCTAssertTrue(first === rebuilt)
        XCTAssertEqual(rebuilt.draftText, "half-written")
        XCTAssertTrue(rebuilt.isUtilityOpen)

        for index in 0..<4 {
            _ = ChatViewModel.shared(session: try session("ses_other\(index)"), connectionManager: manager)
        }
        XCTAssertFalse(ChatViewModel.shared(session: chat, connectionManager: manager) === first, "evicted after 4 newer chats")
    }

    /// The sidebar layout has one detail stack: Settings and the project's screens take turns in it.
    func testDetailPathFollowsTheSidebarSelection() throws {
        let router = AppRouter()
        let chat = try session("ses_1")
        router.openChat(chat)
        XCTAssertEqual(router.detailPath, [.chat(chat)])

        router.navigateToSettings()
        XCTAssertEqual(router.detailPath, [])
        router.detailPath.append(.settings(.servers))
        XCTAssertEqual(router.settingsPath, [.settings(.servers)])
        XCTAssertEqual(router.dashboardPath, [.project("/repo"), .chat(chat)], "the chat stays for the way back")

        router.selectProject("/repo")
        XCTAssertEqual(router.detailPath, [.chat(chat)])
        router.detailPath = []
        XCTAssertEqual(router.dashboardPath, [.project("/repo")], "popping keeps the selected project")
    }
}

