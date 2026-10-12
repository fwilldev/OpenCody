import XCTest
@testable import OpenCody___An_OpenCode_Client

/// Project grouping and custom names (GitHub issue #1).
@MainActor
final class ProjectNamingTests: XCTestCase {

    private func session(_ id: String, directory: String, title: String = "T", updated: Double = 1) throws -> Session {
        let json = """
        {"id":"\(id)","projectID":"p","directory":"\(directory)","title":"\(title)","version":"1",
         "time":{"created":1,"updated":\(updated)}}
        """
        return try JSONDecoder().decode(Session.self, from: Data(json.utf8))
    }

    private func project(_ id: String, worktree: String, name: String? = nil) throws -> Project {
        let nameField = name.map { ",\"name\":\"\($0)\"" } ?? ""
        let json = """
        {"id":"\(id)","worktree":"\(worktree)","time":{"created":1,"updated":1}\(nameField)}
        """
        return try JSONDecoder().decode(Project.self, from: Data(json.utf8))
    }

    func testFoldersWithTheSameNameStaySeparateProjects() throws {
        let model = DashboardViewModel(connectionManager: ConnectionManager())
        model.sessions = [
            try session("ses_1", directory: "/work/a/app"),
            try session("ses_2", directory: "/work/b/app"),
        ]
        let groups = model.projectGroups
        XCTAssertEqual(groups.map(\.directory).sorted(), ["/work/a/app", "/work/b/app"])
        XCTAssertEqual(groups.map(\.name), ["app", "app"])
    }

    func testNamePrecedenceLocalThenServerThenFolder() throws {
        let model = DashboardViewModel(connectionManager: ConnectionManager())
        model.projects = [
            try project("prj_1", worktree: "/repo", name: "Server Name"),
            try project("global", worktree: "/", name: "Global"),
        ]
        XCTAssertEqual(model.projectName(for: "/repo"), "Server Name")
        XCTAssertTrue(model.hasCustomName(directory: "/repo"))

        // The shared `global` project never names a folder.
        XCTAssertEqual(model.projectName(for: "/tmp/scratch"), "scratch")
        XCTAssertFalse(model.hasCustomName(directory: "/tmp/scratch"))
        XCTAssertNil(model.serverProject(for: "/tmp/scratch"))

        model.customProjectNames = ["/repo": "Mine"]
        XCTAssertEqual(model.projectName(for: "/repo"), "Mine")
    }

    func testProjectNameStoreIsPerServerAndEmptyNameResets() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ProjectNamingTests"))
        defaults.removePersistentDomain(forName: "ProjectNamingTests")
        let store = ProjectNameStore(defaults: defaults)
        let serverA = UUID(), serverB = UUID()

        store.setName("  Website  ", directory: "/srv/site", serverID: serverA)
        XCTAssertEqual(store.names(for: serverA), ["/srv/site": "Website"])
        XCTAssertEqual(store.names(for: serverB), [:])

        store.setName("", directory: "/srv/site", serverID: serverA)
        XCTAssertEqual(store.names(for: serverA), [:])
    }

    func testRetitledSessionIsNotEqualSoRowsRerender() throws {
        let original = try session("ses_1", directory: "/repo", title: "Old")
        let renamed = original.retitled("New")
        XCTAssertNotEqual(original, renamed)
        XCTAssertEqual(original.hashValue, renamed.hashValue)
        XCTAssertEqual(renamed.title, "New")
    }
}
