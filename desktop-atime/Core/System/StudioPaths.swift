import Foundation

nonisolated enum StudioPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// `~/Library/Application Support/Hackatime Studio`
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appending(path: "Library/Application Support")
        return base.appending(path: "Hackatime Studio", directoryHint: .isDirectory)
    }

    static var backupsDirectory: URL { supportDirectory.appending(path: "Backups", directoryHint: .isDirectory) }

    /// Creates a private (0700) directory if needed.
    static func ensurePrivateDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
    }

    /// `/Users/me/foo` → `~/foo` for display.
    static func abbreviate(_ path: String) -> String {
        let h = home.path
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }

    static func expandTilde(_ path: String) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") { return home.path + path.dropFirst(1) }
        return path
    }
}
