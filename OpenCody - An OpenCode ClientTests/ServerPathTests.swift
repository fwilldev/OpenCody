import XCTest
@testable import OpenCody___An_OpenCode_Client

/// Server directories from Windows hosts must reach the server unchanged (OC-WINPATH).
final class ServerPathTests: XCTestCase {

    func testWindowsPathsAreAbsolute() {
        XCTAssertTrue(ServerPath.isAbsolute(#"C:\AI\Worker-01\Repo"#))
        XCTAssertTrue(ServerPath.isAbsolute("C:/AI/Worker-01/Repo"))
        XCTAssertTrue(ServerPath.isAbsolute("d:"))
        XCTAssertTrue(ServerPath.isAbsolute(#"\\server\share\Repo"#))
        XCTAssertTrue(ServerPath.isAbsolute("/home/me/repo"))
        XCTAssertFalse(ServerPath.isAbsolute("home/me/repo"))
        XCTAssertFalse(ServerPath.isAbsolute("Cx:/repo"))
    }

    func testNormalizedKeepsWindowsPathsUnchanged() {
        for path in [#"C:\AI\Worker-01\Repo"#, "C:/AI/Worker-01/Repo", #"\\server\share\Repo"#] {
            XCTAssertEqual(ServerPath.normalized(path), path)
        }
    }

    func testNormalizedStandardizesPosixPaths() {
        XCTAssertEqual(ServerPath.normalized("/work/a/../app/"), "/work/app")
    }
}
