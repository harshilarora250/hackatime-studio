import Foundation

nonisolated enum ConnectionState: Equatable, Sendable {
    case unknown
    case checking
    case noKey
    case valid(UserProfile)
    case invalidKey
    case failed(HackatimeAPIError)

    var profile: UserProfile? { if case .valid(let p) = self { return p }; return nil }
    var isValid: Bool { profile != nil }
}

/// Where the API key comes from.
nonisolated enum APIKeySource: Equatable, Sendable {
    case config(String)          // key value (never displayed unmasked by default)
    case vaultCommand(String)    // api_key_vault_cmd
    case environmentOnly         // WAKATIME_API_KEY set in the shell
    case missing

    var key: String? { if case .config(let k) = self { return k }; return nil }
}

nonisolated struct DiagnosticCheck: Identifiable, Equatable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case configuration = "Configuration"
        case connection = "API connection"
        case components = "Tracking components"
        case editor = "Editor integration"
        case activity = "Tracking activity"

        var subtitle: String {
            switch self {
            case .configuration: "Is .wakatime.cfg present and valid?"
            case .connection: "Can Hackatime be reached with your key?"
            case .components: "Is wakatime-cli installed and working?"
            case .editor: "Is the VS Code extension installed?"
            case .activity: "Has Hackatime actually received heartbeats?"
            }
        }
    }

    enum Status: Int, Comparable, Sendable {
        case ok = 0, info, unknown, warning, error
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    enum Fix: Equatable, Sendable {
        case enterAPIKey
        case setHackatimeURL
        case createConfig
        case openConfiguration
        case openAdvanced(String)
        case openEditors
        case openFolders
        case reveal(URL)
        case openURL(URL)
        case removeKey(section: String, key: String)
    }

    var id: String
    var group: Group
    var title: String
    var status: Status
    var detail: String
    var fix: Fix?
    var fixTitle: String?
}

nonisolated struct DiagnosticsInput: Sendable {
    var environment: ShellEnvironment
    var location: ConfigLocation
    var document: INIDocument?
    var configError: String?
    var keySource: APIKeySource
    var apiURL: String?
    var connection: ConnectionState
    var installation: WakatimeInstallation?
    var cliToday: Result<String, CLICheckFailure>?
    var vscode: EditorStatus?
    var vscodeRecommendedID: String
    var vscodeKnown: [KnownExtension]
    var latestAny: MostRecentHeartbeatResponse?
    var latestVSCode: MostRecentHeartbeatResponse?
    var activityError: String?
    var now: Date = Date()
}

nonisolated struct CLICheckFailure: Error, Equatable, Sendable { var message: String }

nonisolated enum DiagnosticsEngine {

    static func evaluate(_ input: DiagnosticsInput) -> [DiagnosticCheck] {
        configuration(input) + connection(input) + components(input) + editor(input) + activity(input)
    }

    // MARK: Configuration

    static func configuration(_ i: DiagnosticsInput) -> [DiagnosticCheck] {
        var out: [DiagnosticCheck] = []
        let g = DiagnosticCheck.Group.configuration

        if let error = i.configError {
            out.append(.init(id: "cfg.read", group: g, title: "Config file can’t be read", status: .error,
                             detail: error, fix: .reveal(i.location.url), fixTitle: "Show in Finder"))
            return out
        }
        guard i.location.exists, let doc = i.document else {
            out.append(.init(id: "cfg.exists", group: g, title: "No config file", status: .error,
                             detail: "\(i.location.displayPath) doesn’t exist. Editor plugins have no API key or API URL to use.",
                             fix: .enterAPIKey, fixTitle: "Set up"))
            return out
        }
        out.append(.init(id: "cfg.exists", group: g, title: "Config file found", status: .ok,
                         detail: "\(i.location.displayPath) (\(i.location.source.rawValue))", fix: .reveal(i.location.url), fixTitle: "Show in Finder"))

        if !i.location.editorsReadSameFile {
            out.append(.init(id: "cfg.xdg", group: g, title: "Editors read a different file", status: .warning,
                             detail: "wakatime-cli uses \(i.location.displayPath), but the VS Code extension reads \(StudioPaths.abbreviate(i.location.editorPluginURL.path)). Keep the API key in both, or move your config to ~/.wakatime.cfg.",
                             fix: .reveal(i.location.url), fixTitle: "Show in Finder"))
        }
        for shadowed in i.location.shadowed {
            out.append(.init(id: "cfg.shadow.\(shadowed.path)", group: g, title: "Unused config file", status: .info,
                             detail: "\(StudioPaths.abbreviate(shadowed.path)) exists but isn’t used, because \(i.location.displayPath) takes precedence.",
                             fix: .reveal(shadowed), fixTitle: "Show in Finder"))
        }

        let issues = doc.issues
        let errors = issues.filter { $0.severity == .error }
        if errors.isEmpty {
            out.append(.init(id: "cfg.syntax", group: g, title: "Syntax is valid", status: .ok,
                             detail: issues.isEmpty ? "wakatime-cli can parse every line." : "\(issues.count) minor warning(s) below."))
        } else {
            out.append(.init(id: "cfg.syntax", group: g, title: "Syntax errors", status: .error,
                             detail: errors.map(\.message).joined(separator: "\n"), fix: .openConfiguration, fixTitle: "Open raw file"))
        }
        for (n, issue) in issues.filter({ $0.severity == .warning }).enumerated() {
            out.append(.init(id: "cfg.warn.\(n)", group: g, title: "Config warning", status: .warning, detail: issue.message,
                             fix: .openConfiguration, fixTitle: "Review"))
        }

        switch i.keySource {
        case .config:
            out.append(.init(id: "cfg.key", group: g, title: "API key is set", status: .ok, detail: "Stored as api_key in [settings]."))
        case .vaultCommand(let cmd):
            out.append(.init(id: "cfg.key", group: g, title: "API key comes from a command", status: .info,
                             detail: "api_key_vault_cmd = \(cmd). Studio doesn’t run this command, so it can’t validate the key or load your dashboard. Add api_key to use Studio’s dashboard.",
                             fix: .enterAPIKey, fixTitle: "Add key"))
        case .environmentOnly:
            out.append(.init(id: "cfg.key", group: g, title: "API key only in environment", status: .warning,
                             detail: "WAKATIME_API_KEY is set in your shell, but not in the config. GUI editors may not see shell variables, and Studio can’t read it.",
                             fix: .enterAPIKey, fixTitle: "Add key to config"))
        case .missing:
            out.append(.init(id: "cfg.key", group: g, title: "No API key", status: .error,
                             detail: "api_key is missing from [settings].", fix: .enterAPIKey, fixTitle: "Add key"))
        }

        if let url = i.apiURL, !url.isEmpty {
            if let e = HackatimeEndpoints(apiURL: url) {
                if e.looksLikeWakaTime {
                    out.append(.init(id: "cfg.url", group: g, title: "API URL points to WakaTime", status: .error,
                                     detail: "api_url = \(url). Heartbeats go to wakatime.com, not Hackatime.",
                                     fix: .setHackatimeURL, fixTitle: "Use Hackatime"))
                } else if e.isOfficialHackatime && !url.contains("/api/hackatime/v1") {
                    out.append(.init(id: "cfg.url", group: g, title: "Unexpected API URL path", status: .warning,
                                     detail: "Hackatime’s WakaTime-compatible API lives at \(ConfigSchema.hackatimeAPIURL).",
                                     fix: .setHackatimeURL, fixTitle: "Fix URL"))
                } else {
                    out.append(.init(id: "cfg.url", group: g, title: e.isOfficialHackatime ? "API URL is Hackatime" : "Custom API URL", status: e.isOfficialHackatime ? .ok : .info,
                                     detail: url))
                }
            } else {
                out.append(.init(id: "cfg.url", group: g, title: "API URL is invalid", status: .error, detail: url,
                                 fix: .setHackatimeURL, fixTitle: "Use Hackatime"))
            }
        } else {
            out.append(.init(id: "cfg.url", group: g, title: "No API URL", status: .error,
                             detail: "Without api_url, wakatime-cli sends heartbeats to wakatime.com instead of Hackatime.",
                             fix: .setHackatimeURL, fixTitle: "Use Hackatime"))
        }

        if (doc.value(section: "settings", key: "disabled") ?? "").lowercased() == "true" {
            out.append(.init(id: "cfg.disabled", group: g, title: "Tracking is paused", status: .warning,
                             detail: "disabled = true — the VS Code extension won’t send heartbeats.",
                             fix: .removeKey(section: "settings", key: "disabled"), fixTitle: "Resume"))
        }
        if (doc.value(section: "settings", key: "exclude") ?? "").lowercased() == "true" {
            out.append(.init(id: "cfg.exclude.all", group: g, title: "Everything is excluded", status: .error,
                             detail: "exclude = true excludes every file, so nothing is tracked.",
                             fix: .openAdvanced("exclude"), fixTitle: "Review"))
        }
        if (doc.value(section: "settings", key: "debug") ?? "").lowercased() == "true" {
            out.append(.init(id: "cfg.debug", group: g, title: "Debug logging is on", status: .info,
                             detail: "Useful while troubleshooting; turn it off afterwards to keep logs small.",
                             fix: .removeKey(section: "settings", key: "debug"), fixTitle: "Turn off"))
        }
        if let imported = doc.value(section: "settings", key: "import_cfg"), !imported.isEmpty {
            let path = StudioPaths.expandTilde(imported)
            let exists = FileManager.default.fileExists(atPath: path)
            out.append(.init(id: "cfg.import", group: g, title: exists ? "Imports another config" : "Imported config missing",
                             status: exists ? .info : .warning,
                             detail: "import_cfg = \(imported). Values in that file override this one; Studio only edits \(i.location.displayPath).",
                             fix: exists ? .reveal(URL(fileURLWithPath: path)) : .openAdvanced("import_cfg"), fixTitle: exists ? "Show in Finder" : "Review"))
        }
        if i.environment.hasAPIURLVariable {
            out.append(.init(id: "env.url", group: g, title: "WAKATIME_API_URL is set", status: .info,
                             detail: "The VS Code extension may prefer this environment variable over api_url in the config."))
        }
        return out
    }

    // MARK: Connection

    static func connection(_ i: DiagnosticsInput) -> [DiagnosticCheck] {
        let g = DiagnosticCheck.Group.connection
        switch i.connection {
        case .unknown, .checking:
            return [.init(id: "api", group: g, title: "Checking connection…", status: .unknown, detail: "")]
        case .noKey:
            return [.init(id: "api", group: g, title: "Not checked", status: .unknown,
                          detail: "Studio needs an api_key in the config to contact Hackatime.", fix: .enterAPIKey, fixTitle: "Add key")]
        case .valid(let profile):
            return [
                .init(id: "api.reach", group: g, title: "Hackatime is reachable", status: .ok, detail: HackatimeEndpoints(apiURL: i.apiURL ?? "")?.root.host() ?? ""),
                .init(id: "api.key", group: g, title: "API key is valid", status: .ok,
                      detail: "Signed in as \(profile.username.map { "@\($0)" } ?? profile.bestName)\(profile.timezone.map { " · \($0)" } ?? "")"),
            ]
        case .invalidKey:
            return [
                .init(id: "api.reach", group: g, title: "Hackatime is reachable", status: .ok, detail: ""),
                .init(id: "api.key", group: g, title: "API key was rejected", status: .error,
                      detail: HackatimeAPIError.unauthorized.errorDescription ?? "", fix: .enterAPIKey, fixTitle: "Replace key"),
            ]
        case .failed(let error):
            return [.init(id: "api.reach", group: g, title: "Can’t reach Hackatime", status: .error,
                          detail: error.errorDescription ?? "Unknown error")]
        }
    }

    // MARK: Components

    static func components(_ i: DiagnosticsInput) -> [DiagnosticCheck] {
        let g = DiagnosticCheck.Group.components
        guard let inst = i.installation else {
            return [.init(id: "cli", group: g, title: "Checking wakatime-cli…", status: .unknown, detail: "")]
        }
        var out: [DiagnosticCheck] = []
        if let cli = inst.activeCLI {
            let how = inst.globalCLI != nil ? "global install" : "downloaded by an editor extension"
            out.append(.init(id: "cli", group: g, title: "wakatime-cli is installed", status: .ok,
                             detail: "\(inst.cliVersion ?? "unknown version") · \(StudioPaths.abbreviate(cli.path)) (\(how))",
                             fix: .reveal(cli), fixTitle: "Show in Finder"))
        } else {
            out.append(.init(id: "cli", group: g, title: "wakatime-cli not found", status: .warning,
                             detail: "Editor extensions download it into \(StudioPaths.abbreviate(inst.resourcesDirectory.path)) the first time they run. Install the VS Code extension and open VS Code once.",
                             fix: .openEditors, fixTitle: "Editors"))
        }

        switch i.cliToday {
        case .success(let text):
            out.append(.init(id: "cli.today", group: g, title: "wakatime-cli can use your config", status: .ok,
                             detail: "`wakatime-cli --today` succeeded\(text.isEmpty ? "" : ": “\(text)”")."))
        case .failure(let f):
            out.append(.init(id: "cli.today", group: g, title: "wakatime-cli check failed", status: .error,
                             detail: f.message, fix: .openConfiguration, fixTitle: "Configuration"))
        case nil:
            if inst.isCLIInstalled {
                out.append(.init(id: "cli.today", group: g, title: "wakatime-cli end-to-end check", status: .unknown,
                                 detail: "Run diagnostics to test the CLI against your config."))
            }
        }

        if let count = inst.offlineQueueCount {
            out.append(.init(id: "cli.offline", group: g, title: count == 0 ? "Offline queue is empty" : "\(count) heartbeat(s) waiting to sync",
                             status: count == 0 ? .ok : (count > 200 ? .warning : .info),
                             detail: count == 0 ? "Nothing is stuck locally." : "They’re stored in \(StudioPaths.abbreviate(inst.offlineQueueFile.path)) and are sent the next time an editor sends a heartbeat while online."))
        }
        if !inst.recentLogErrors.isEmpty {
            out.append(.init(id: "cli.log", group: g, title: "Recent errors in the log", status: .warning,
                             detail: inst.recentLogErrors.joined(separator: "\n"), fix: .reveal(inst.logFile), fixTitle: "Show log"))
        } else if inst.logFileExists {
            out.append(.init(id: "cli.log", group: g, title: "No recent errors in the log", status: .ok,
                             detail: StudioPaths.abbreviate(inst.logFile.path), fix: .reveal(inst.logFile), fixTitle: "Show log"))
        }
        return out
    }

    // MARK: Editor

    static func editor(_ i: DiagnosticsInput) -> [DiagnosticCheck] {
        let g = DiagnosticCheck.Group.editor
        guard let vs = i.vscode else {
            return [.init(id: "vscode", group: g, title: "Checking VS Code…", status: .unknown, detail: "")]
        }
        var out: [DiagnosticCheck] = []
        guard vs.isAppInstalled else {
            return [.init(id: "vscode.app", group: g, title: "VS Code isn’t installed", status: .info,
                          detail: "Studio V1 manages the VS Code integration. Other editors can still be configured manually using the Hackatime docs.",
                          fix: .openURL(URL(string: "https://code.visualstudio.com")!), fixTitle: "Get VS Code")]
        }
        out.append(.init(id: "vscode.app", group: g, title: "VS Code is installed", status: .ok,
                         detail: "Version \(vs.appVersion ?? "unknown")\(vs.isRunning ? " · running" : "")"))
        if let err = vs.detectionError {
            out.append(.init(id: "vscode.detect", group: g, title: "Couldn’t read VS Code’s extension list", status: .warning, detail: err))
        }

        let installedKnown = i.vscodeKnown.filter { vs.isInstalled($0.id) }
        let trackers = installedKnown.filter { $0.role != .unofficial }
        if trackers.isEmpty {
            out.append(.init(id: "vscode.ext", group: g, title: "No tracking extension installed", status: .error,
                             detail: "Install “Hackatime Time Tracker” so VS Code sends heartbeats.", fix: .openEditors, fixTitle: "Install"))
        } else {
            for ext in trackers {
                out.append(.init(id: "vscode.ext.\(ext.id)", group: g,
                                 title: "\(ext.name) is installed", status: .ok,
                                 detail: "v\(vs.version(of: ext.id) ?? "?") · found in \(vs.detectionSource). Studio can’t see whether it’s disabled inside VS Code."))
            }
        }
        if trackers.count > 1 {
            out.append(.init(id: "vscode.dupe", group: g, title: "Two tracking extensions installed", status: .warning,
                             detail: "Both send heartbeats for the same activity. Keep one (Hackatime Time Tracker is recommended).",
                             fix: .openEditors, fixTitle: "Manage"))
        }
        for ext in installedKnown where ext.role == .unofficial {
            out.append(.init(id: "vscode.unofficial.\(ext.id)", group: g, title: "Unofficial extension installed", status: .warning,
                             detail: "\(ext.name) by \(ext.publisher) isn’t supported by Hackatime and may not track correctly.",
                             fix: .openEditors, fixTitle: "Manage"))
        }
        return out
    }

    // MARK: Activity

    static func activity(_ i: DiagnosticsInput) -> [DiagnosticCheck] {
        let g = DiagnosticCheck.Group.activity
        guard i.connection.isValid else {
            return [.init(id: "hb", group: g, title: "Can’t verify heartbeats", status: .unknown,
                          detail: "Needs a working API connection.")]
        }
        if let error = i.activityError {
            return [.init(id: "hb", group: g, title: "Couldn’t load heartbeats", status: .warning, detail: error)]
        }
        var out: [DiagnosticCheck] = []
        out.append(heartbeatCheck(id: "hb.any", title: "Last heartbeat (any editor)", response: i.latestAny, now: i.now, group: g))
        if i.vscode?.isAppInstalled == true {
            out.append(heartbeatCheck(id: "hb.vscode", title: "Last heartbeat from VS Code", response: i.latestVSCode, now: i.now, group: g))
        }
        return out
    }

    private static func heartbeatCheck(id: String, title: String, response: MostRecentHeartbeatResponse?, now: Date,
                                       group: DiagnosticCheck.Group) -> DiagnosticCheck {
        guard let response else {
            return .init(id: id, group: group, title: title, status: .unknown, detail: "Not loaded yet.")
        }
        guard response.hasHeartbeat, let hb = response.heartbeat, let time = hb.time else {
            return .init(id: id, group: group, title: title, status: .warning,
                         detail: "Hackatime has never received one. Open a project in your editor and edit a file for a minute.")
        }
        let age = now.timeIntervalSince(time)
        let rel = Formatters.relative(time, now: now)
        let where_ = [hb.project, hb.language, hb.editor].compactMap { $0 }.joined(separator: " · ")
        let status: DiagnosticCheck.Status = age < 60 * 60 * 24 ? .ok : (age < 60 * 60 * 24 * 7 ? .info : .warning)
        return .init(id: id, group: group, title: title, status: status, detail: "\(rel)\(where_.isEmpty ? "" : " — \(where_)")")
    }
}
