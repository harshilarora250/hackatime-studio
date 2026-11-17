import Foundation
import Testing
@testable import Hackatime_Studio

@Suite("Diagnostics engine")
struct DiagnosticsTests {

    func input(cfg: String?, connection: ConnectionState = .unknown, keySource: APIKeySource? = nil,
               vscode: EditorStatus? = nil) -> DiagnosticsInput {
        let url = URL(fileURLWithPath: "/tmp/x/.wakatime.cfg")
        let doc = cfg.map(INIDocument.init(text:))
        let key = doc?.value(section: "settings", key: "api_key")
        return DiagnosticsInput(
            environment: .init(wakatimeHome: nil, xdgConfigHome: nil, hasAPIKeyVariable: false, hasAPIURLVariable: false, resolvedFromShell: false),
            location: ConfigLocation(url: url, source: .home, exists: cfg != nil, editorPluginURL: url, shadowed: []),
            document: doc, configError: nil,
            keySource: keySource ?? (key.map { .config($0) } ?? .missing),
            apiURL: doc?.value(section: "settings", key: "api_url"),
            connection: connection, installation: nil, cliToday: nil, vscode: vscode,
            vscodeRecommendedID: "hackatime.hackatime-time-tracker",
            vscodeKnown: [
                KnownExtension(id: "hackatime.hackatime-time-tracker", name: "Hackatime Time Tracker", publisher: "Hack Club", role: .recommended, marketplaceURL: URL(string: "https://x")!),
                KnownExtension(id: "wakatime.vscode-wakatime", name: "WakaTime", publisher: "WakaTime", role: .compatible, marketplaceURL: URL(string: "https://x")!),
            ],
            latestAny: nil, latestVSCode: nil, activityError: nil)
    }

    func check(_ checks: [DiagnosticCheck], _ id: String) -> DiagnosticCheck? { checks.first { $0.id == id } }

    @Test func missingConfigIsAnError() {
        let checks = DiagnosticsEngine.evaluate(input(cfg: nil))
        #expect(check(checks, "cfg.exists")?.status == .error)
    }

    @Test func wakatimeURLIsFlagged() {
        let checks = DiagnosticsEngine.evaluate(input(cfg: "[settings]\napi_key = k\napi_url = https://api.wakatime.com/api/v1\n"))
        #expect(check(checks, "cfg.url")?.status == .error)
        #expect(check(checks, "cfg.url")?.fix == .setHackatimeURL)
    }

    @Test func missingURLIsFlagged() {
        let checks = DiagnosticsEngine.evaluate(input(cfg: "[settings]\napi_key = k\n"))
        #expect(check(checks, "cfg.url")?.status == .error)
    }

    @Test func configPresentDoesNotImplyTracking() {
        let checks = DiagnosticsEngine.evaluate(input(cfg: "[settings]\napi_key = k\napi_url = \(ConfigSchema.hackatimeAPIURL)\n"))
        #expect(check(checks, "cfg.url")?.status == .ok)
        // Without a validated connection, heartbeats are explicitly "not verified", never OK.
        #expect(check(checks, "hb")?.status == .unknown)
    }

    @Test func pausedTrackingIsAWarning() {
        let checks = DiagnosticsEngine.evaluate(input(cfg: "[settings]\napi_key = k\ndisabled = true\n"))
        #expect(check(checks, "cfg.disabled")?.status == .warning)
    }

    @Test func duplicateExtensionsWarn() {
        let vs = EditorStatus(appURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), appVersion: "1.0", cliURL: nil, isRunning: false,
                              installed: [InstalledExtension(id: "hackatime.hackatime-time-tracker"), InstalledExtension(id: "wakatime.vscode-wakatime")],
                              detectionSource: "test", detectionError: nil)
        let checks = DiagnosticsEngine.evaluate(input(cfg: "[settings]\napi_key = k\n", vscode: vs))
        #expect(check(checks, "vscode.dupe")?.status == .warning)
    }

    @Test func missingExtensionIsAnError() {
        let vs = EditorStatus(appURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), appVersion: "1.0", cliURL: nil, isRunning: false,
                              installed: [], detectionSource: "test", detectionError: nil)
        let checks = DiagnosticsEngine.evaluate(input(cfg: "[settings]\napi_key = k\n", vscode: vs))
        #expect(check(checks, "vscode.ext")?.status == .error)
    }

    @Test func noCheckLeaksTheKey() {
        let key = "waka_12345678-aaaa-bbbb-cccc-1234567890ab"
        let checks = DiagnosticsEngine.evaluate(input(cfg: "[settings]\napi_key = \(key)\nbroken line \(key)\n", connection: .invalidKey))
        for c in checks { #expect(!c.detail.contains("1234567890ab") && !c.title.contains("1234567890ab")) }
    }
}

@Suite("Uninstall planning")
struct UninstallTests {

    let url = URL(fileURLWithPath: "/tmp/none/.wakatime.cfg")
    var location: ConfigLocation { ConfigLocation(url: url, source: .home, exists: true, editorPluginURL: url, shadowed: []) }
    let known = [KnownExtension(id: "hackatime.hackatime-time-tracker", name: "Hackatime Time Tracker", publisher: "Hack Club", role: .recommended, marketplaceURL: URL(string: "https://x")!),
                 KnownExtension(id: "wakatime.vscode-wakatime", name: "WakaTime", publisher: "WakaTime", role: .compatible, marketplaceURL: URL(string: "https://x")!)]
    var vscode: EditorStatus {
        EditorStatus(appURL: URL(fileURLWithPath: "/A.app"), appVersion: "1", cliURL: nil, isRunning: false,
                     installed: [InstalledExtension(id: "hackatime.hackatime-time-tracker"), InstalledExtension(id: "wakatime.vscode-wakatime")],
                     detectionSource: "t", detectionError: nil)
    }

    @Test func studioManagedOnlyTouchesWhatStudioCreated() {
        var ledger = StudioLedger()
        ledger.installedExtensions = ["hackatime.hackatime-time-tracker"]
        ledger.configPath = url.path
        ledger.addedKeys = ["settings.heartbeat_rate_limit_seconds", "settings.exclude", "projectmap.^/a/", "settings.gone"]
        let doc = INIDocument(text: "[settings]\napi_key = mine\nheartbeat_rate_limit_seconds = 30\nexclude = x\n[projectmap]\n^/a/ = a\n^/b/ = b\n")
        let plan = UninstallPlanner.plan(mode: .studioManaged, ledger: ledger, location: location, document: doc,
                                         vscode: vscode, knownExtensions: known, installation: nil)
        let ids = plan.items.map(\.id)
        #expect(ids.contains("ext.hackatime.hackatime-time-tracker"))
        #expect(!ids.contains("ext.wakatime.vscode-wakatime"), "pre-existing WakaTime extension is left alone")
        guard case .removeConfigKeys(let refs)? = plan.items.first(where: { $0.id == "cfg.keys" })?.action else {
            Issue.record("expected key removal"); return
        }
        let keys = Set(refs.map { "\($0.section).\($0.key)" })
        #expect(keys == ["settings.heartbeat_rate_limit_seconds", "projectmap.^/a/"])
        #expect(!keys.contains("settings.api_key"), "user's own key is never removed")
        #expect(!keys.contains("settings.exclude"), "shared exclude list is never removed wholesale")
    }

    @Test func keysRecordedForAnotherFileAreIgnored() {
        var ledger = StudioLedger()
        ledger.configPath = "/somewhere/else/.wakatime.cfg"
        ledger.addedKeys = ["settings.api_key"]
        let plan = UninstallPlanner.plan(mode: .studioManaged, ledger: ledger, location: location, document: INIDocument(text: "[settings]\napi_key = x\n"),
                                         vscode: nil, knownExtensions: known, installation: nil)
        #expect(plan.isEmpty)
    }

    @Test func studioCreatedFileIsTrashedWholeInStudioMode() {
        var ledger = StudioLedger()
        ledger.createdConfigPath = url.path
        let plan = UninstallPlanner.plan(mode: .studioManaged, ledger: ledger, location: location, document: INIDocument(text: "[settings]\n"),
                                         vscode: nil, knownExtensions: known, installation: nil)
        #expect(plan.items.contains { $0.action == .trashConfigFile(url) })
    }

    @Test func everythingIncludesAllDetectedExtensionsAndConfig() {
        let plan = UninstallPlanner.plan(mode: .everything, ledger: StudioLedger(), location: location, document: INIDocument(),
                                         vscode: vscode, knownExtensions: known, installation: nil)
        #expect(plan.items.filter { if case .uninstallExtension = $0.action { return true }; return false }.count == 2)
        #expect(plan.items.contains { $0.action == .trashConfigFile(url) })
        #expect(plan.items.contains { $0.id == "other.editors" && !$0.isRemovable }, "undetectable things are disclosed, not claimed")
    }

    @Test func emptyPlanWhenStudioDidNothing() {
        let plan = UninstallPlanner.plan(mode: .studioManaged, ledger: StudioLedger(), location: location, document: INIDocument(text: "[settings]\napi_key = x\n"),
                                         vscode: vscode, knownExtensions: known, installation: nil)
        #expect(plan.isEmpty)
    }

    @Test func ledgerRecordsOnlyNewKeys() {
        var ledger = StudioLedger()
        let doc = INIDocument(text: "[settings]\napi_key = old\n")
        ledger.recordAdditions([.settings("api_key", "new"), .settings("api_url", "u")], before: doc)
        #expect(ledger.addedKeys == ["settings.api_url"])
        ledger.forgetRemovals([.settings("api_url", nil)])
        #expect(ledger.addedKeys.isEmpty)
    }
}

@Suite("Dashboard models")
struct DashboardModelTests {
    @Test func layoutNormalisationAddsNewWidgetsHidden() {
        let layout = DashboardLayout(widgets: [WidgetConfig(kind: .today)]).normalized()
        #expect(layout.widgets.count == WidgetKind.allCases.count)
        #expect(layout.visible.map(\.kind) == [.today])
    }

    @Test func totalsUseSummaryDays() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = Date()
        let key = DashboardSnapshot.dayKey(today, calendar: cal)
        let json = #"{"data":[{"grand_total":{"total_seconds":3600},"range":{"date":"\#(key)"}}]}"#
        let days = try JSONDecoder().decode(SummariesResponse.self, from: Data(json.utf8)).data
        let snap = DashboardSnapshot(fetchedAt: today, timeZone: cal.timeZone, today: nil, days: days, stats: [:],
                                     spansToday: nil, latest: nil, failures: [:])
        #expect(snap.seconds(on: today) == 3600)
        #expect(snap.monthTotal == 3600)
        #expect(snap.weekTotal == 3600)
    }
}
