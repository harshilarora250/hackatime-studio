import AppKit
import Foundation
import Observation

enum Route: Hashable, CaseIterable {
    case dashboard, lapse, configuration, folders, editors, diagnostics, settings
}

enum SetupFlow: Equatable {
    case enterKey
    case success
    case guided(Int)
}

struct Toast: Identifiable {
    enum Style { case success, error, info }
    let id = UUID()
    var message: String
    var style: Style
    var undo: (() -> Void)?
}

/// The single source of app state. Everything shown in the UI is derived from the real config
/// file, the real API, and the real local installation — nothing is cached as "truth" except
/// Studio's own UI preferences.
@MainActor
@Observable
final class AppModel {

    // MARK: Navigation & setup
    var route: Route = .dashboard
    var setupFlow: SetupFlow?
    var toast: Toast?

    // MARK: Config
    private(set) var environment: ShellEnvironment = .processOnly
    private(set) var location: ConfigLocation
    private(set) var document: INIDocument?
    private(set) var configError: String?
    private(set) var configReloadedExternally = false
    private var fingerprint = ConfigFingerprint(exists: false)

    // MARK: Connection & data
    private(set) var connection: ConnectionState = .unknown
    var layout: DashboardLayout { didSet { layout.save() } }
    private(set) var snapshot: DashboardSnapshot?
    private(set) var isLoadingDashboard = false
    private(set) var dashboardError: String?

    // MARK: Editors & system
    let vscode = VSCodeIntegration()
    private(set) var vscodeStatus: EditorStatus?
    private(set) var editorBusy: String?
    private(set) var latestVSCode: MostRecentHeartbeatResponse?
    private(set) var latestAny: MostRecentHeartbeatResponse?
    private(set) var activityError: String?
    private(set) var installation: WakatimeInstallation?
    private(set) var cliToday: Result<String, CLICheckFailure>?
    private(set) var isRunningDiagnostics = false

    // MARK: Lapse
    let lapse = LapseStore()

    // MARK: Studio bookkeeping & prefs
    private(set) var ledger = StudioLedger.load()
    var appearance: AppearancePreference {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: StudioDefaults.appearance); appearance.apply() }
    }
    var refreshInterval: RefreshInterval {
        didSet { UserDefaults.standard.set(refreshInterval.rawValue, forKey: StudioDefaults.refresh); scheduleAutoRefresh() }
    }
    var workingFolders: [String] {
        didSet { UserDefaults.standard.set(workingFolders, forKey: StudioDefaults.workingFolders) }
    }

    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private var watchTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var didBootstrap = false

    init() {
        let defaults = UserDefaults.standard
        self.location = ConfigLocator.locate(environment: .processOnly)
        self.layout = DashboardLayout.load()
        self.appearance = AppearancePreference(rawValue: defaults.string(forKey: StudioDefaults.appearance) ?? "") ?? .system
        self.refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: StudioDefaults.refresh)) ?? .five
        if defaults.object(forKey: StudioDefaults.refresh) == nil { self.refreshInterval = .five }
        self.workingFolders = defaults.stringArray(forKey: StudioDefaults.workingFolders) ?? []
        reloadConfig()
        lapse.notify = { [weak self] toast in self?.toast = toast }
    }

    // MARK: - Derived config values

    func value(_ key: String, section: String = "settings") -> String? {
        guard let document else { return nil }
        if let v = document.value(section: section, key: key) { return v }
        if let option = ConfigSchema.option(key, section: section) {
            for alias in option.aliases { if let v = document.value(section: section, key: alias) { return v } }
        }
        return nil
    }

    var keySource: APIKeySource {
        if let key = value("api_key")?.trimmingCharacters(in: .whitespaces), !key.isEmpty { return .config(key) }
        if let cmd = value("api_key_vault_cmd"), !cmd.isEmpty { return .vaultCommand(cmd) }
        if environment.hasAPIKeyVariable { return .environmentOnly }
        return .missing
    }

    var apiKey: String? { keySource.key }
    var configuredAPIURL: String? { value("api_url").flatMap { $0.isEmpty ? nil : $0 } }

    /// The URL Studio queries. When the config has no (or a WakaTime) URL, Studio still talks to
    /// Hackatime — Diagnostics flags the config problem separately.
    var studioAPIURL: String {
        if let url = configuredAPIURL, let e = HackatimeEndpoints(apiURL: url), !e.looksLikeWakaTime { return url }
        return ConfigSchema.hackatimeAPIURL
    }

    var endpoints: HackatimeEndpoints? { HackatimeEndpoints(apiURL: studioAPIURL) }
    var projectRules: ParsedProjectRules { ProjectRules.parse(document ?? INIDocument()) }
    var trackingPaused: Bool { value("disabled")?.lowercased() == "true" }

    var diagnostics: [DiagnosticCheck] {
        DiagnosticsEngine.evaluate(DiagnosticsInput(
            environment: environment, location: location, document: document, configError: configError,
            keySource: keySource, apiURL: configuredAPIURL, connection: connection, installation: installation,
            cliToday: cliToday, vscode: vscodeStatus, vscodeRecommendedID: vscode.recommendedExtension?.id ?? "",
            vscodeKnown: vscode.knownExtensions, latestAny: latestAny, latestVSCode: latestVSCode,
            activityError: activityError))
    }

    var overallHealth: DiagnosticCheck.Status {
        diagnostics.map(\.status).filter { $0 != .unknown && $0 != .info }.max() ?? .unknown
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        appearance.apply()
        startWatchingConfig()

        let resolved = await ShellEnvironment.resolve()
        if resolved != environment {
            environment = resolved
            relocate()
        }
        if keySource.key == nil && !UserDefaults.standard.bool(forKey: StudioDefaults.setupCompleted) {
            setupFlow = .enterKey
        }
        await refreshAll(includeCLICheck: false)
        scheduleAutoRefresh()
    }

    /// The browser-style reload: config from disk, API connection, dashboard, editors, diagnostics.
    func refreshAll(includeCLICheck: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }
        relocate()
        await validateConnection()
        async let dash: Void = refreshDashboard()
        async let editors: Void = refreshEditors()
        async let system: Void = refreshInstallation(runCLICheck: includeCLICheck)
        // Lapse is only fetched once its page has been opened.
        async let lapseRefresh: Void = refreshLapseIfOpened()
        _ = await (dash, editors, system, lapseRefresh)
    }

    /// The Hackatime user ID Lapse links accounts by (from `/users/current`).
    var hackatimeUserID: String? {
        #if DEBUG
        // Developer tool: preview the Lapse page for any Hackatime user without their key.
        if let id = ProcessInfo.processInfo.environment["STUDIO_DEBUG_LAPSE_HACKATIME_ID"] { return id }
        #endif
        return connection.profile?.id
    }

    private func refreshLapseIfOpened() async {
        if lapse.phase != .idle { await refreshLapse(force: true) }
    }

    func refreshLapse(force: Bool = false) async {
        await lapse.refresh(hackatimeID: hackatimeUserID, force: force)
    }

    func appBecameActive() {
        guard didBootstrap, let interval = refreshInterval.seconds else { return }
        if let last = lastRefresh, Date().timeIntervalSince(last) < interval { return }
        Task { await refreshDashboard() }
    }

    private func scheduleAutoRefresh() {
        autoRefreshTask?.cancel()
        guard let seconds = refreshInterval.seconds else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                // Only poll while the app is frontmost, to avoid needless API requests.
                if NSApp.isActive, self.connection.isValid { await self.refreshDashboard() }
            }
        }
    }

    // MARK: - Config loading & editing

    private func relocate() {
        let newLocation = ConfigLocator.locate(environment: environment)
        if newLocation != location { location = newLocation }
        reloadConfig()
    }

    func reloadConfig(external: Bool = false) {
        location = ConfigLocator.locate(environment: environment)
        fingerprint = ConfigStore.fingerprint(location)
        do {
            document = try ConfigStore.read(location)
            configError = nil
        } catch {
            document = nil
            configError = error.localizedDescription
        }
        if external { configReloadedExternally = true }
    }

    func dismissExternalNotice() { configReloadedExternally = false }

    private func startWatchingConfig() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                let current = ConfigStore.fingerprint(self.location)
                if current != self.fingerprint {
                    let hadKey = self.apiKey
                    self.reloadConfig(external: true)
                    if self.apiKey != hadKey { await self.validateConnection() }
                }
            }
        }
    }

    /// Applies targeted edits to the live file (re-read from disk first), with a backup and undo.
    @discardableResult
    func apply(_ edits: [ConfigEdit], message: String? = nil, showToast: Bool = true) -> Bool {
        guard !edits.isEmpty else { return true }
        let before = document
        let existed = location.exists
        let backupsBefore = Set(ConfigStore.backups().map(\.url))
        do {
            try ConfigStore.apply(edits, to: location)
            ledger.scope(to: location.url.path)
            ledger.recordAdditions(edits, before: before)
            ledger.forgetRemovals(edits)
            if !existed { ledger.createdConfigPath = location.url.path }
            ledger.save()
            reloadConfig()
            configReloadedExternally = false
            if showToast {
                let newBackup = ConfigStore.backups().first { !backupsBefore.contains($0.url) }
                toast = Toast(message: message ?? "Saved to \(location.displayPath)", style: .success,
                              undo: newBackup.map { backup in { [weak self] in self?.restore(backup) } })
            }
            return true
        } catch {
            toast = Toast(message: error.localizedDescription, style: .error)
            return false
        }
    }

    func set(_ key: String, _ value: String?, section: String = "settings") {
        apply([.set(section: section, key: key, value: value)])
    }

    func restore(_ backup: ConfigBackup) {
        do {
            try ConfigStore.restore(backup, to: location)
            reloadConfig()
            toast = Toast(message: "Restored the previous version", style: .info)
            Task { await validateConnection() }
        } catch {
            toast = Toast(message: error.localizedDescription, style: .error)
        }
    }

    func createEmptyConfig() {
        apply([.settings("api_url", ConfigSchema.hackatimeAPIURL)], message: "Created \(location.displayPath)")
    }

    // MARK: - API key & connection

    func validateConnection() async {
        guard let key = apiKey else {
            connection = .noKey
            return
        }
        if case .valid = connection {} else { connection = .checking }
        do {
            let client = try HackatimeClient(apiURL: studioAPIURL, apiKey: key)
            let profile = try await client.currentUser()
            connection = .valid(profile)
        } catch HackatimeAPIError.unauthorized {
            connection = .invalidKey
        } catch let error as HackatimeAPIError {
            connection = .failed(error)
        } catch is CancellationError {
        } catch {
            connection = .failed(.network(error.localizedDescription))
        }
    }

    enum KeyValidation: Equatable {
        case valid(UserProfile)
        case invalid
        case unreachable(String)
    }

    /// Validates a key against Hackatime without saving anything.
    func check(key: String) async -> KeyValidation {
        do {
            let client = try HackatimeClient(apiURL: studioAPIURL, apiKey: key)
            return .valid(try await client.currentUser())
        } catch HackatimeAPIError.unauthorized {
            return .invalid
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    /// Writes the key (and the Hackatime API URL / rate limit when missing) to the config.
    @discardableResult
    func saveAPIKey(_ key: String, profile: UserProfile?) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var edits: [ConfigEdit] = [.settings("api_key", trimmed)]
        let url = configuredAPIURL
        if url == nil || HackatimeEndpoints(apiURL: url!) == nil || HackatimeEndpoints(apiURL: url!)?.looksLikeWakaTime == true {
            edits.append(.settings("api_url", ConfigSchema.hackatimeAPIURL))
        }
        if value("heartbeat_rate_limit_seconds") == nil {
            edits.append(.settings("heartbeat_rate_limit_seconds", "30"))
        }
        guard apply(edits, message: "API key saved to \(location.displayPath)") else { return false }
        if let profile { connection = .valid(profile) } else { Task { await validateConnection() } }
        UserDefaults.standard.set(true, forKey: StudioDefaults.setupCompleted)
        Task { await refreshDashboard() }
        return true
    }

    func useHackatimeURL() {
        apply([.settings("api_url", ConfigSchema.hackatimeAPIURL)], message: "API URL set to Hackatime")
        Task { await validateConnection() }
    }

    func finishSetup() {
        UserDefaults.standard.set(true, forKey: StudioDefaults.setupCompleted)
        setupFlow = nil
    }

    // MARK: - Dashboard

    func refreshDashboard() async {
        guard let key = apiKey, connection.isValid || connection == .checking || connection == .unknown,
              let client = try? HackatimeClient(apiURL: studioAPIURL, apiKey: key) else { return }
        isLoadingDashboard = true
        defer { isLoadingDashboard = false }

        let tz = connection.profile?.timeZone ?? .current
        var calendar = Calendar.current
        calendar.timeZone = tz
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        // One summaries request covers the graph, this week, last week and this month (≤ 366 days).
        let weeks = min(max(layout.config(.activity)?.weeks ?? 26, 4), 52)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let graphStart = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: weekStart)!
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        // The desktop activity widget shows up to 16 weeks, whatever the dashboard graph is set to.
        let widgetStart = calendar.date(byAdding: .day, value: -7 * 15, to: weekStart)!
        let earliest = max([graphStart, monthStart, lastWeekStart, widgetStart].min()!, calendar.date(byAdding: .day, value: -365, to: startOfToday)!)

        var ranges = Set(layout.visible.filter(\.kind.supportsRange).map(\.range))
        ranges.insert(.week) // streak comes with any stats call

        var failures: [String: String] = [:]
        func capture<T>(_ name: String, _ result: Result<T, Error>) -> T? {
            switch result {
            case .success(let v): return v
            case .failure(let e): failures[name] = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription; return nil
            }
        }

        async let todayR = Self.result { try await client.statusBarToday() }
        let summaryStart = DashboardSnapshot.dayKey(earliest, calendar: calendar)
        let summaryEnd = DashboardSnapshot.dayKey(now, calendar: calendar)
        let fixedCalendar = calendar
        async let daysR = Self.result { try await client.summaries(from: summaryStart, to: summaryEnd) }
        async let spansR = Self.result { try await client.spans(from: startOfToday, to: now) }
        async let latestR = Self.result { try await client.mostRecentHeartbeat() }
        let statsResults = await withTaskGroup(of: (StatsRange, Result<UserStats, Error>).self) { group in
            for range in ranges {
                let (s, e) = range.interval(now: now, calendar: fixedCalendar)
                group.addTask { (range, await Self.result { try await client.stats(from: s, to: e) }) }
            }
            var out: [(StatsRange, Result<UserStats, Error>)] = []
            for await r in group { out.append(r) }
            return out
        }

        let today = capture("today", await todayR)
        let days = capture("summaries", await daysR) ?? snapshot?.days ?? []
        let spans = capture("spans", await spansR)
        let latest = capture("latest", await latestR)
        var stats: [StatsRange: UserStats] = [:]
        for (range, result) in statsResults {
            if let s = capture("stats.\(range.rawValue)", result) { stats[range] = s }
        }

        if failures.values.contains(where: { $0 == HackatimeAPIError.unauthorized.errorDescription }) {
            connection = .invalidKey
        }
        snapshot = DashboardSnapshot(fetchedAt: now, timeZone: tz, today: today, days: days, stats: stats,
                                     spansToday: spans, latest: latest, failures: failures)
        if let latest { latestAny = latest }
        if let snapshot { WidgetBridge.publish(snapshot) }
        dashboardError = failures.count >= 4 ? failures.values.first : nil
        lastRefresh = now
    }

    nonisolated private static func result<T: Sendable>(_ op: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await op()) } catch { return .failure(error) }
    }

    // MARK: - Editors

    func refreshEditors() async {
        vscodeStatus = await vscode.detect()
        await refreshActivity()
    }

    func refreshActivity() async {
        guard let key = apiKey, connection.isValid, let client = try? HackatimeClient(apiURL: studioAPIURL, apiKey: key) else { return }
        do {
            async let any = client.mostRecentHeartbeat()
            async let code = client.mostRecentHeartbeat(editor: vscode.heartbeatEditorName)
            latestAny = try await any
            latestVSCode = try await code
            activityError = nil
        } catch {
            activityError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func install(_ ext: KnownExtension) async {
        editorBusy = ext.id
        defer { editorBusy = nil }
        do {
            try await vscode.install(ext)
            vscodeStatus = await vscode.detect()
            if vscodeStatus?.isInstalled(ext.id) == true {
                ledger.installedExtensions.insert(ext.id.lowercased())
                ledger.save()
                let reload = vscodeStatus?.isRunning == true ? " Reload the VS Code window to activate it." : ""
                toast = Toast(message: "\(ext.name) installed.\(reload)", style: .success)
            } else {
                toast = Toast(message: "VS Code reported success, but \(ext.name) isn’t in the extension list yet. Click Refresh in a moment.", style: .info)
            }
        } catch {
            toast = Toast(message: error.localizedDescription, style: .error)
        }
    }

    func uninstall(_ ext: KnownExtension) async {
        editorBusy = ext.id
        defer { editorBusy = nil }
        do {
            try await vscode.uninstall(ext)
            ledger.installedExtensions.remove(ext.id.lowercased())
            ledger.save()
            vscodeStatus = await vscode.detect()
            toast = Toast(message: "\(ext.name) removed from VS Code.", style: .success)
        } catch {
            toast = Toast(message: error.localizedDescription, style: .error)
        }
    }

    // MARK: - System & diagnostics

    func refreshInstallation(runCLICheck: Bool) async {
        installation = await WakatimeInstallation.detect(environment: environment, document: document)
        if runCLICheck { await runCLICheckNow() }
    }

    func runCLICheckNow() async {
        guard let cli = installation?.activeCLI, location.exists else { cliToday = nil; return }
        switch await WakatimeInstallation.cliTodayCheck(cli: cli) {
        case .success(let text): cliToday = .success(text)
        case .failure(let error):
            cliToday = .failure(CLICheckFailure(message: Redaction.redactSecrets(in: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                                                                                 knownSecrets: [apiKey].compactMap { $0 })))
        }
    }

    func runDiagnostics() async {
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }
        relocate()
        await validateConnection()
        async let editors: Void = refreshEditors()
        async let system: Void = refreshInstallation(runCLICheck: true)
        _ = await (editors, system)
    }

    func perform(_ fix: DiagnosticCheck.Fix) {
        switch fix {
        case .enterAPIKey: route = .configuration; setupFlow = apiKey == nil ? .enterKey : nil
        case .setHackatimeURL: useHackatimeURL()
        case .createConfig: createEmptyConfig()
        case .openConfiguration, .openAdvanced: route = .configuration
        case .openEditors: route = .editors
        case .openFolders: route = .folders
        case .reveal(let url):
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            else { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
        case .openURL(let url): NSWorkspace.shared.open(url)
        case .removeKey(let section, let key): apply([.set(section: section, key: key, value: nil)])
        }
    }

    // MARK: - Folders

    /// Top-level folders shown on the Folders page: user-added ones plus any rule roots in the config.
    var folderRoots: [String] {
        let rules = projectRules.rules.map(\.path)
        var all = workingFolders
        for path in rules where !all.contains(where: { path.lowercased() == $0.lowercased() || path.lowercased().hasPrefix($0.lowercased() + "/") }) {
            all.append(path)
        }
        // Collapse folders that are inside another listed folder.
        return all.filter { p in !all.contains { other in other != p && p.lowercased().hasPrefix(other.lowercased() + "/") } }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func mode(for path: String) -> FolderMode {
        projectRules.rules.first { $0.id == path.lowercased() }?.mode ?? .automatic
    }

    func setMode(_ mode: FolderMode, for path: String) {
        let normalized = ProjectRules.normalize(path)
        var rules = projectRules.rules.filter { $0.id != normalized.lowercased() }
        if mode != .automatic { rules.append(FolderRule(path: normalized, mode: mode)) }
        do {
            let edits = try ProjectRules.edits(from: document ?? INIDocument(), to: rules)
            apply(edits, message: edits.isEmpty ? nil : "Updated project rules in \(location.displayPath)")
        } catch {
            toast = Toast(message: error.localizedDescription, style: .error)
        }
    }

    func addWorkingFolder(_ url: URL) {
        let path = ProjectRules.normalize(url.path)
        if !workingFolders.contains(where: { $0.lowercased() == path.lowercased() }) { workingFolders.append(path) }
    }

    /// Removes a folder from Studio's list and clears every rule at or below it.
    func removeWorkingFolder(_ path: String) {
        workingFolders.removeAll { $0.lowercased() == path.lowercased() }
        let prefix = path.lowercased() + "/"
        let remaining = projectRules.rules.filter { $0.id != path.lowercased() && !$0.id.hasPrefix(prefix) }
        if remaining.count != projectRules.rules.count,
           let edits = try? ProjectRules.edits(from: document ?? INIDocument(), to: remaining) {
            apply(edits, message: "Removed rules for \(StudioPaths.abbreviate(path))")
        }
    }

    // MARK: - Uninstall

    func uninstallPlan(_ mode: UninstallMode) -> UninstallPlan {
        UninstallPlanner.plan(mode: mode, ledger: ledger, location: location, document: document, vscode: vscodeStatus,
                              knownExtensions: vscode.knownExtensions, installation: installation)
    }

    func execute(_ plan: UninstallPlan) async -> [UninstallOutcome] {
        var outcomes: [UninstallOutcome] = []
        for item in plan.items where item.isSelected && item.isRemovable {
            switch item.action {
            case .uninstallExtension(let id):
                guard let ext = vscode.known(id) else { continue }
                do {
                    try await vscode.uninstall(ext)
                    ledger.installedExtensions.remove(id.lowercased())
                    outcomes.append(.init(id: item.id, title: item.title, succeeded: true, message: "Removed"))
                } catch {
                    outcomes.append(.init(id: item.id, title: item.title, succeeded: false, message: error.localizedDescription))
                }
            case .removeConfigKeys(let refs):
                let ok = apply(refs.map { .set(section: $0.section, key: $0.key, value: nil) }, showToast: false)
                outcomes.append(.init(id: item.id, title: item.title, succeeded: ok,
                                      message: ok ? "Removed (backup saved)" : "Couldn’t update the config file"))
            case .trashConfigFile(let url), .trashDirectory(let url):
                do {
                    let target = url.resolvingSymlinksInPath()
                    if case .trashConfigFile = item.action {
                        try ConfigStore.backup(target, into: StudioPaths.backupsDirectory)
                        if target.path == location.url.resolvingSymlinksInPath().path { ledger.createdConfigPath = nil; ledger.addedKeys = [] }
                    }
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    outcomes.append(.init(id: item.id, title: item.title, succeeded: true, message: "Moved to the Trash"))
                } catch {
                    outcomes.append(.init(id: item.id, title: item.title, succeeded: false, message: error.localizedDescription))
                }
            case .manual:
                break
            }
        }
        ledger.save()
        reloadConfig()
        await refreshAll(includeCLICheck: false)
        return outcomes
    }
}
