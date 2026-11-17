import Foundation

/// Every configuration option Studio exposes, taken from wakatime-cli's USAGE.md and source
/// (`pkg/params`, `cmd/logfile`) plus the keys the VS Code extensions read (`disabled`,
/// `status_bar_team`). Nothing in here is invented: if a key is not listed, Studio shows it as
/// an "other key" and preserves it untouched.
nonisolated struct ConfigOption: Identifiable, Hashable, Sendable {

    enum Kind: Hashable, Sendable {
        case bool
        case int(min: Int, max: Int?)
        case string
        case secret
        case path
        case url
        /// A newline-separated list of POSIX regexes (multi-line INI value).
        case regexList
        /// `true`, `false`, or a list of regexes (e.g. `hide_file_names`).
        case boolOrRegexList
    }

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case connection = "Connection"
        case tracking = "Tracking scope"
        case privacy = "Privacy"
        case projects = "Projects & Git"
        case ai = "AI coding"
        case editor = "Editor status bar"
        case network = "Network"
        case troubleshooting = "Troubleshooting"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .connection: "bolt.horizontal.circle"
            case .tracking: "scope"
            case .privacy: "eye.slash"
            case .projects: "folder.badge.gearshape"
            case .ai: "sparkles"
            case .editor: "menubar.rectangle"
            case .network: "network"
            case .troubleshooting: "ladybug"
            }
        }
    }

    /// Who reads the key. Shown so users know where a setting takes effect.
    enum Consumer: String, Hashable, Sendable {
        case cli = "wakatime-cli"
        case editorPlugin = "Editor plugins"
        case both = "wakatime-cli & plugins"
    }

    let section: String
    let key: String
    let title: String
    let summary: String
    let kind: Kind
    /// The default wakatime-cli uses when the key is absent (display only — never written implicitly).
    let defaultValue: String?
    let category: Category
    let isBasic: Bool
    let consumer: Consumer
    /// Legacy spellings wakatime-cli still reads as a fallback.
    let aliases: [String]
    var id: String { "\(section).\(key)" }

    init(_ key: String, section: String = "settings", title: String, summary: String, kind: Kind,
         default defaultValue: String? = nil, category: Category, basic: Bool = false,
         consumer: Consumer = .cli, aliases: [String] = []) {
        self.section = section; self.key = key; self.title = title; self.summary = summary
        self.kind = kind; self.defaultValue = defaultValue; self.category = category
        self.isBasic = basic; self.consumer = consumer; self.aliases = aliases
    }

    var searchText: String { "\(key) \(title) \(summary) \(category.rawValue) \(aliases.joined(separator: " "))".lowercased() }
}

/// Free-form `pattern = value` sections.
nonisolated struct ConfigMapSection: Identifiable, Hashable, Sendable {
    let name: String
    let title: String
    let summary: String
    let keyLabel: String
    let valueLabel: String
    let valueIsSecret: Bool
    var id: String { name }
}

nonisolated enum ConfigSchema {

    static let hackatimeAPIURL = "https://hackatime.hackclub.com/api/hackatime/v1"
    static let wakatimeDefaultAPIURL = "https://api.wakatime.com/api/v1"

    static let options: [ConfigOption] = [
        // Connection
        .init("api_key", title: "API key",
              summary: "Identifies your Hackatime account when heartbeats are sent. Keep it private.",
              kind: .secret, category: .connection, basic: true, consumer: .both, aliases: ["apikey"]),
        .init("api_url", title: "API URL",
              summary: "Where heartbeats are sent. Hackatime uses \(hackatimeAPIURL). When unset, wakatime-cli sends to WakaTime’s own servers.",
              kind: .url, default: wakatimeDefaultAPIURL, category: .connection, basic: true, consumer: .both),
        .init("api_key_vault_cmd", title: "API key command",
              summary: "A command that prints your API key (for example from a password manager). Space-separated executable and arguments; no shell syntax. Used only when api_key is empty.",
              kind: .string, category: .connection),
        .init("heartbeat_rate_limit_seconds", title: "Heartbeat rate limit",
              summary: "Send heartbeats at most once per this many seconds. Hackatime’s setup uses 30. Set 0 to disable rate limiting.",
              kind: .int(min: 0, max: 3600), default: "120", category: .connection, basic: true),
        .init("offline", title: "Offline queue",
              summary: "Save heartbeats to ~/.wakatime/offline_heartbeats.bdb when the API can’t be reached and sync them later.",
              kind: .bool, default: "true", category: .connection),
        .init("disabled", title: "Tracking paused",
              summary: "When true, the VS Code extension stops sending heartbeats. Other editors may ignore this key.",
              kind: .bool, default: "false", category: .connection, basic: true, consumer: .editorPlugin),
        .init("hostname", title: "Machine name",
              summary: "Name reported for this computer. By default the system hostname is used.",
              kind: .string, category: .connection),

        // Tracking scope
        .init("exclude", title: "Exclude paths",
              summary: "Files whose path matches any of these POSIX regexes are never tracked. Matching is case-insensitive. “true” excludes everything.",
              kind: .boolOrRegexList, category: .tracking, basic: true, aliases: ["ignore"]),
        .init("include", title: "Include paths",
              summary: "Files matching these regexes are tracked even when they also match an exclude pattern.",
              kind: .boolOrRegexList, category: .tracking),
        .init("include_only_with_project_file", title: "Only track folders with a .wakatime-project file",
              summary: "Disables tracking everywhere except folders (or parents) that contain a .wakatime-project file.",
              kind: .bool, default: "false", category: .tracking, basic: true),
        .init("exclude_unknown_project", title: "Ignore activity without a project",
              summary: "Drops heartbeats when no project can be detected (no project file, project map match, git repo or editor workspace).",
              kind: .bool, default: "false", category: .tracking),
        .init("guess_language", title: "Guess language from contents",
              summary: "Detect the programming language from file contents when the extension is ambiguous.",
              kind: .bool, default: "false", category: .tracking),

        // Privacy
        .init("hide_file_names", title: "Hide file names",
              summary: "Obfuscate file names (extension is kept). true/false, or regexes to hide only matching paths. Hiding names can make activity ineligible for Hack Club programme review.",
              kind: .boolOrRegexList, default: "false", category: .privacy, basic: true,
              aliases: ["hide_filenames", "hidefilenames"]),
        .init("hide_project_names", title: "Hide project names",
              summary: "Obfuscate project names. When a project folder is detected, a .wakatime-project file with a random name is created.",
              kind: .boolOrRegexList, default: "false", category: .privacy,
              aliases: ["hide_projectnames", "hideprojectnames"]),
        .init("hide_branch_names", title: "Hide branch names",
              summary: "Don’t send git branch names. true/false or regexes.",
              kind: .boolOrRegexList, default: "false", category: .privacy,
              aliases: ["hide_branchnames", "hidebranchnames"]),
        .init("hide_dependencies", title: "Hide dependencies",
              summary: "Don’t send the imports/libraries detected in the focused file. true/false or regexes.",
              kind: .boolOrRegexList, default: "false", category: .privacy),
        .init("hide_project_folder", title: "Send paths relative to the project",
              summary: "Send src/file.ts instead of /Users/you/projects/bar/src/file.ts, so the full path never leaves your Mac.",
              kind: .bool, default: "false", category: .privacy, basic: true),

        // Projects & Git
        .init("project_from_git_remote", section: "git", title: "Name projects after the git remote",
              summary: "Use the repository name from the git remote (e.g. owner/repo) as the project name instead of the folder name.",
              kind: .bool, default: "false", category: .projects),
        .init("submodules_disabled", section: "git", title: "Ignore git submodules",
              summary: "true to treat submodules as part of the parent repo, or regexes matched against submodule paths.",
              kind: .boolOrRegexList, default: "false", category: .projects),

        // AI
        .init("sync_ai_disabled", title: "Disable AI coding detection",
              summary: "Stop parsing AI tool transcripts (Claude, Codex, Cursor…) to detect AI-assisted edits.",
              kind: .bool, default: "false", category: .ai),
        .init("exclude_ai", title: "Exclude paths from AI tracking",
              summary: "Skip “ai coding” heartbeats for matching file paths. Human activity is still tracked.",
              kind: .regexList, category: .ai),

        // Editor status bar
        .init("status_bar_enabled", title: "Show status bar item",
              summary: "Show the Hackatime/WakaTime item in the editor status bar.",
              kind: .bool, default: "true", category: .editor, consumer: .editorPlugin),
        .init("status_bar_coding_activity", title: "Show today’s time in status bar",
              summary: "When off, only the icon is shown.",
              kind: .bool, default: "true", category: .editor, consumer: .editorPlugin),
        .init("status_bar_team", title: "Show team total",
              summary: "Show team totals in the VS Code status bar when available.",
              kind: .bool, default: "true", category: .editor, consumer: .editorPlugin),
        .init("status_bar_show_categories", title: "Show category breakdown",
              summary: "wakatime-cli --today includes per-category durations.",
              kind: .bool, default: "false", category: .editor),
        .init("status_bar_hide_minutes", title: "Hide minutes past an hour",
              summary: "“3 hrs 57 mins” is shown as “3 hrs”.",
              kind: .bool, default: "false", category: .editor),
        .init("status_bar_max_categories", title: "Max categories",
              summary: "Limit the number of categories shown. 0 means no limit.",
              kind: .int(min: 0, max: 50), default: "0", category: .editor),

        // Network
        .init("proxy", title: "Proxy",
              summary: "HTTPS, SOCKS or NTLM proxy, e.g. https://user:pass@host:port or socks5://host:port.",
              kind: .string, category: .network, consumer: .both),
        .init("no_ssl_verify", title: "Skip SSL verification",
              summary: "Disable certificate verification. Only for broken corporate proxies — this is insecure.",
              kind: .bool, default: "false", category: .network, consumer: .both),
        .init("ssl_certs_file", title: "CA certificates file",
              summary: "Path to a custom CA bundle. By default the bundled Let’s Encrypt CA and system CAs are used.",
              kind: .path, category: .network),
        .init("timeout", title: "Request timeout (seconds)",
              summary: "Connection timeout when talking to the API.",
              kind: .int(min: 1, max: 600), default: "120", category: .network),

        // Troubleshooting
        .init("debug", title: "Debug logging",
              summary: "Write verbose messages to the log file. Turn off after troubleshooting.",
              kind: .bool, default: "false", category: .troubleshooting, consumer: .both),
        .init("log_file", title: "Log file",
              summary: "Custom log location.",
              kind: .path, default: "~/.wakatime/wakatime.log", category: .troubleshooting),
        .init("metrics", title: "Collect performance metrics",
              summary: "Write pprof metrics to ~/.wakatime/metrics.",
              kind: .bool, default: "false", category: .troubleshooting, consumer: .both),
        .init("send_diagnostics_on_errors", title: "Send diagnostics on errors",
              summary: "Upload diagnostics to the API when wakatime-cli hits an error.",
              kind: .bool, default: "false", category: .troubleshooting),
        .init("import_cfg", title: "Import another config",
              summary: "Path to another wakatime.cfg whose values override this file.",
              kind: .path, category: .troubleshooting),
    ]

    static let mapSections: [ConfigMapSection] = [
        .init(name: "projectmap", title: "Project map",
              summary: "Rename projects by path. Regex → project name; {0}, {1}… insert capture groups. Studio’s Folders & Projects page writes rules here.",
              keyLabel: "Path regex", valueLabel: "Project name", valueIsSecret: false),
        .init(name: "project_api_key", title: "Per-project API keys",
              summary: "Send heartbeats for matching paths with a different API key.",
              keyLabel: "Path regex", valueLabel: "API key", valueIsSecret: true),
        .init(name: "api_urls", title: "Additional API servers",
              summary: "Also send heartbeats for matching paths to another WakaTime-compatible server. Value: api_url|api_key. All matching patterns receive heartbeats.",
              keyLabel: "Path regex", valueLabel: "api_url|api_key", valueIsSecret: true),
        .init(name: "git_submodule_projectmap", title: "Submodule project map",
              summary: "Rename git submodule projects by submodule path.",
              keyLabel: "Submodule regex", valueLabel: "Project name", valueIsSecret: false),
    ]

    static func option(_ key: String, section: String = "settings") -> ConfigOption? {
        options.first { $0.key == key && $0.section == section }
    }

    /// True when the key (or one of its aliases) is part of the schema.
    static func isKnown(section: String, key: String) -> Bool {
        let s = section.lowercased(), k = key.lowercased()
        if mapSections.contains(where: { $0.name == s }) { return true }
        return options.contains { $0.section == s && ($0.key == k || $0.aliases.contains(k)) }
    }
}
