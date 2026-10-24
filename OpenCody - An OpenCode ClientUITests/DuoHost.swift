import XCTest

/// Requests to `scripts/duo-host.sh` on the Mac: unfold/fold the iPhone Duo simulator (a
/// resizable app session at the inner display's size) and screenshot the inner display.
/// XCUIDevice and XCUIScreen can do neither. Nil unless `OPENCODY_DUO_HOST_DIR` is set.
struct DuoHost {
    let dir: String

    init?() {
        guard let dir = ProcessInfo.processInfo.environment["OPENCODY_DUO_HOST_DIR"], !dir.isEmpty else { return nil }
        self.dir = dir
    }

    /// Sends one request and waits until the host has handled it.
    func send(_ request: String) {
        let done = "\(dir)/done"
        try? FileManager.default.removeItem(atPath: done)
        try? request.write(toFile: "\(dir)/request", atomically: true, encoding: .utf8)
        for _ in 0..<120 {
            let handled = try? String(contentsOfFile: done, encoding: .utf8)
            if handled?.trimmingCharacters(in: .whitespacesAndNewlines) == request { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("Duo host did not handle \(request)")
    }
}
