import Foundation

/// What is installed under `~/.wakatime` (or `$WAKATIME_HOME/.wakatime`) — the directory editor
/// plugins use to download and run wakatime-cli, plus its logs and offline queue.
nonisolated struct WakatimeInstallation: Equatable, Sendable {
    var resourcesDirectory: URL
    var resourcesDirectoryExists: Bool
    /// The CLI binary the editor extensions would run (`wakatime-cli-darwin-<arch>` in resources).
    var bundledCLI: URL?
    /// A `wakatime-cli` found on PATH (e.g. Homebrew). Extensions prefer it when present.
    var globalCLI: URL?
    var cliVersion: String?
    var logFile: URL
    var logFileExists: Bool
    var logLastModified: Date?
    var offlineQueueFile: URL
    var offlineQueueCount: Int?
    /// Redacted recent error lines from the log.
    var recentLogErrors: [String]

    var activeCLI: URL? { globalCLI ?? bundledCLI }
    var isCLIInstalled: Bool { activeCLI != nil }

    /// Everything inside the resources directory (for uninstall previews).
    var resourceItems: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: resourcesDirectory, includingPropertiesForKeys: nil)) ?? []
    }

    static var architectureSuffix: String {
        #if arch(arm64)
        "arm64"
        #else
        "amd64"
        #endif
    }

    @concurrent
    static func detect(environment: ShellEnvironment, document: INIDocument?) async -> WakatimeInstallation {
        let fm = FileManager.default
        let base = environment.wakatimeHome.map { URL(fileURLWithPath: StudioPaths.expandTilde($0), isDirectory: true) } ?? StudioPaths.home
        let resources = base.appending(path: ".wakatime", directoryHint: .isDirectory)

        let bundledCandidates = [
            resources.appending(path: "wakatime-cli-darwin-\(architectureSuffix)"),
            resources.appending(path: "wakatime-cli"),
        ]
        let bundled = bundledCandidates.first { fm.isExecutableFile(atPath: $0.path) }
        let global = ["/opt/homebrew/bin/wakatime-cli", "/usr/local/bin/wakatime-cli", "/usr/bin/wakatime-cli"]
            .map(URL.init(fileURLWithPath:))
            .first { fm.isExecutableFile(atPath: $0.path) }

        var logFile = resources.appending(path: "wakatime.log")
        if let custom = document?.value(section: "settings", key: "log_file"), !custom.isEmpty {
            logFile = URL(fileURLWithPath: StudioPaths.expandTilde(custom))
        }
        let logAttrs = try? fm.attributesOfItem(atPath: logFile.path)

        var install = WakatimeInstallation(
            resourcesDirectory: resources,
            resourcesDirectoryExists: fm.fileExists(atPath: resources.path),
            bundledCLI: bundled, globalCLI: global, cliVersion: nil,
            logFile: logFile, logFileExists: logAttrs != nil,
            logLastModified: logAttrs?[.modificationDate] as? Date,
            offlineQueueFile: resources.appending(path: "offline_heartbeats.bdb"),
            offlineQueueCount: nil,
            recentLogErrors: [])

        if let cli = install.activeCLI {
            if let r = try? await ProcessRunner.run(cli, arguments: ["--version"], timeout: 8), r.succeeded {
                install.cliVersion = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let r = try? await ProcessRunner.run(cli, arguments: ["--offline-count"], timeout: 8), r.succeeded {
                install.offlineQueueCount = Int(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        install.recentLogErrors = recentErrors(in: logFile)
        return install
    }

    /// Runs `wakatime-cli --today`: the CLI reads the real config and calls the configured API.
    /// This proves the CLI + config + key + API work together without sending a heartbeat.
    @concurrent
    static func cliTodayCheck(cli: URL) async -> Result<String, Error> {
        do {
            let r = try await ProcessRunner.run(cli, arguments: ["--today"], timeout: 25)
            if r.succeeded {
                return .success(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let message = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(CLICheckError(message: r.timedOut ? "timed out" : Redaction.redactSecrets(in: message),
                                          exitCode: r.status))
        } catch {
            return .failure(error)
        }
    }

    struct CLICheckError: LocalizedError {
        var message: String
        var exitCode: Int32
        var errorDescription: String? {
            // Exit codes from wakatime-cli/pkg/exitcode.
            switch exitCode {
            case 102: "wakatime-cli got an error from the API or couldn’t reach it (exit 102)."
            case 103: "wakatime-cli couldn’t parse the config file (exit 103)."
            case 104: "wakatime-cli says the API key is invalid (exit 104)."
            case 112: "wakatime-cli is being rate-limited (exit 112)."
            default: message.isEmpty ? "wakatime-cli exited with code \(exitCode)." : message
            }
        }
    }

    /// The last few log lines at error level, redacted.
    private static func recentErrors(in log: URL, limit: Int = 5) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 64 * 1024
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd() else { return [] }
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        let errors = lines.filter { $0.contains("\"level\":\"error\"") || $0.contains("\"level\":\"fatal\"") }
        return errors.suffix(limit).map { line in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return Redaction.redactSecrets(in: String(line.prefix(300)))
            }
            let time = obj["now"] as? String ?? obj["time"] as? String ?? ""
            let message = obj["message"] as? String ?? obj["msg"] as? String ?? line
            return Redaction.redactSecrets(in: "\(time) \(message)".trimmingCharacters(in: .whitespaces))
        }
    }
}
