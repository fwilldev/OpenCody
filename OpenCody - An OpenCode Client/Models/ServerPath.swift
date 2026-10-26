import Foundation

/// Directories as the server reports them, which are Windows paths on a Windows host.
///
/// The device's URL APIs are POSIX-only: they treat `C:\Repo` as relative and resolve it
/// against `/`, so the server would receive `/C:\Repo`.
enum ServerPath {
    /// A drive path (`C:\…`, `C:/…`) or a UNC path (`\\server\share`).
    static func isWindows(_ path: String) -> Bool {
        path.hasPrefix(#"\\"#) || path.wholeMatch(of: #/[A-Za-z]:([\\\/].*)?/#) != nil
    }

    static func isAbsolute(_ path: String) -> Bool {
        path.hasPrefix("/") || isWindows(path)
    }

    /// Standardizes POSIX paths; Windows paths are returned exactly as given.
    static func normalized(_ path: String) -> String {
        guard !isWindows(path) else { return path }
        return URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
