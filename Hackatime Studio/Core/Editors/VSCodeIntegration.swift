import AppKit
import Foundation

/// Visual Studio Code. Detection reads `~/.vscode/extensions/extensions.json` (the file VS Code
/// itself maintains); installs and removals go through VS Code's bundled `code` CLI, only after
/// the user clicks a button.
@MainActor
struct VSCodeIntegration: EditorIntegration {
    let id = "vscode"
    let displayName = "Visual Studio Code"
    let heartbeatEditorName = "vscode"
    static let bundleIdentifier = "com.microsoft.VSCode"
    let setupDocsURL = URL(string: "https://hackatime.hackclub.com/docs/editors/vs-code")!

    let knownExtensions: [KnownExtension] = [
        KnownExtension(id: "hackatime.hackatime-time-tracker", name: "Hackatime Time Tracker", publisher: "Hack Club",
                       role: .recommended,
                       marketplaceURL: URL(string: "https://marketplace.visualstudio.com/items?itemName=hackatime.hackatime-time-tracker")!),
        KnownExtension(id: "wakatime.vscode-wakatime", name: "WakaTime", publisher: "WakaTime",
                       role: .compatible,
                       marketplaceURL: URL(string: "https://marketplace.visualstudio.com/items?itemName=WakaTime.vscode-wakatime")!),
        KnownExtension(id: "wonkystudio.hackatime", name: "Hackatime (unofficial)", publisher: "WonkyStudio",
                       role: .unofficial,
                       marketplaceURL: URL(string: "https://marketplace.visualstudio.com/items?itemName=WonkyStudio.hackatime")!),
    ]

    var extensionsDirectory: URL { StudioPaths.home.appending(path: ".vscode/extensions", directoryHint: .isDirectory) }

    func detect() async -> EditorStatus {
        let workspace = NSWorkspace.shared
        let appURL = workspace.urlForApplication(withBundleIdentifier: Self.bundleIdentifier)
            ?? ["/Applications/Visual Studio Code.app", StudioPaths.home.path + "/Applications/Visual Studio Code.app"]
                .map(URL.init(fileURLWithPath:))
                .first { FileManager.default.fileExists(atPath: $0.path) }
        let version = appURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        let cli = appURL.map { $0.appending(path: "Contents/Resources/app/bin/code") }
            .flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty

        let knownIDs = Set(knownExtensions.map { $0.id.lowercased() })
        let (installed, source, error) = await Self.readInstalledExtensions(in: extensionsDirectory, filter: knownIDs)
        return EditorStatus(appURL: appURL, appVersion: version, cliURL: cli, isRunning: running,
                            installed: installed, detectionSource: source, detectionError: error)
    }

    func install(_ ext: KnownExtension) async throws {
        try await runCLI(["--install-extension", ext.id])
    }

    func uninstall(_ ext: KnownExtension) async throws {
        try await runCLI(["--uninstall-extension", ext.id])
    }

    func openExtensionPage(_ ext: KnownExtension) {
        // Opens the extension page inside VS Code when it's installed, otherwise the web Marketplace.
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil,
           let deepLink = URL(string: "vscode:extension/\(ext.id)") {
            NSWorkspace.shared.open(deepLink)
        } else {
            NSWorkspace.shared.open(ext.marketplaceURL)
        }
    }

    private func runCLI(_ arguments: [String]) async throws {
        let status = await detect()
        guard status.isAppInstalled else { throw EditorIntegrationError.editorNotInstalled(displayName) }
        guard let cli = status.cliURL else { throw EditorIntegrationError.cliMissing(displayName) }
        // The bundled `code` script runs VS Code's CLI headlessly (no window opens).
        let result = try await ProcessRunner.run(cli, arguments: arguments, timeout: 180)
        guard result.succeeded else {
            let output = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw EditorIntegrationError.commandFailed(result.timedOut
                ? "VS Code’s CLI didn’t finish within 3 minutes."
                : "VS Code’s CLI reported an error: \(Redaction.redactSecrets(in: String(output.prefix(400))))")
        }
    }

    /// Parses VS Code's own extension registry. Falls back to folder names when the JSON is absent.
    @concurrent
    nonisolated static func readInstalledExtensions(in directory: URL, filter: Set<String>)
        async -> ([InstalledExtension], String, String?) {
        let fm = FileManager.default
        let registry = directory.appending(path: "extensions.json")
        let obsolete = Set(((try? Data(contentsOf: directory.appending(path: ".obsolete")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]).keys.map { $0.lowercased() })

        if let data = try? Data(contentsOf: registry) {
            guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return ([], "~/.vscode/extensions/extensions.json", "VS Code’s extensions.json couldn’t be parsed.")
            }
            var result: [InstalledExtension] = []
            for item in items {
                guard let identifier = item["identifier"] as? [String: Any],
                      let id = (identifier["id"] as? String)?.lowercased(), filter.contains(id) else { continue }
                let relative = item["relativeLocation"] as? String
                if let relative, obsolete.contains(relative.lowercased()) { continue }
                let path = (item["location"] as? [String: Any])?["path"] as? String
                    ?? relative.map { directory.appending(path: $0).path }
                let location = path.map(URL.init(fileURLWithPath:))
                if let location, !fm.fileExists(atPath: location.path) { continue }
                result.append(InstalledExtension(id: id, version: item["version"] as? String, location: location))
            }
            return (dedupe(result), "~/.vscode/extensions/extensions.json", nil)
        }

        guard fm.fileExists(atPath: directory.path) else { return ([], "~/.vscode/extensions", nil) }
        let folders = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        var result: [InstalledExtension] = []
        for folder in folders where !obsolete.contains(folder.lowercased()) {
            let lower = folder.lowercased()
            for id in filter where lower.hasPrefix(id + "-") {
                let version = String(folder.dropFirst(id.count + 1)).components(separatedBy: "-").first
                result.append(InstalledExtension(id: id, version: version, location: directory.appending(path: folder)))
            }
        }
        return (dedupe(result), "~/.vscode/extensions (folder names)", nil)
    }

    private nonisolated static func dedupe(_ items: [InstalledExtension]) -> [InstalledExtension] {
        var byID: [String: InstalledExtension] = [:]
        for item in items {
            if let existing = byID[item.id],
               (existing.version ?? "").compare(item.version ?? "", options: .numeric) == .orderedDescending { continue }
            byID[item.id] = item
        }
        return byID.values.sorted { $0.id < $1.id }
    }
}
