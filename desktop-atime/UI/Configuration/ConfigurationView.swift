import AppKit
import SwiftUI

struct ConfigurationView: View {
    enum Tab: Hashable { case basic, advanced, file }
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .basic

    var body: some View {
        Page {
            PageHeader(title: "Configuration", subtitle: "Edits go straight to \(model.location.displayPath), the file your editors already use.") {
                ChipPicker(options: [(Tab.basic, "Basic"), (.advanced, "Advanced"), (.file, "File")], selection: $tab)
            }

            if model.configReloadedExternally {
                Panel(padding: 12) {
                    HStack {
                        StatusLine(status: .info, title: "Reloaded", detail: "The config file changed outside Studio, so Studio reloaded it.")
                        Spacer()
                        Button("OK") { model.dismissExternalNotice() }.buttonStyle(.studio(.secondary, compact: true))
                    }
                }
            }
            if let error = model.configError {
                Panel { StatusLine(status: .error, title: "Studio can’t read the config file", detail: error) }
            } else if !model.location.exists {
                Panel {
                    HStack {
                        StatusLine(status: .warning, title: "No config file yet",
                                   detail: "\(model.location.displayPath) will be created when you save your API key or any setting.")
                        Spacer()
                        Button("Set up") { model.setupFlow = .enterKey }.buttonStyle(.studioPrimary)
                    }
                }
            }

            switch tab {
            case .basic: BasicConfigView(showAdvanced: { tab = .advanced })
            case .advanced: AdvancedConfigView()
            case .file: ConfigFileView()
            }
        }
    }
}

// MARK: - Basic

struct BasicConfigView: View {
    var showAdvanced: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Connection")
                Panel {
                    VStack(alignment: .leading, spacing: 0) {
                        APIKeyEditor()
                        Hairline().padding(.vertical, 6)
                        APIURLRow()
                        Hairline()
                        TrackingToggleRow()
                        Hairline()
                        OptionRow(option: ConfigSchema.option("heartbeat_rate_limit_seconds")!)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "What gets tracked") {
                    Button("Folders & Projects →") { model.route = .folders }.buttonStyle(.studioQuiet)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 0) {
                        OptionRow(option: ConfigSchema.option("include_only_with_project_file")!)
                        Hairline()
                        OptionRow(option: ConfigSchema.option("exclude")!)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Privacy")
                Panel {
                    VStack(alignment: .leading, spacing: 0) {
                        OptionRow(option: ConfigSchema.option("hide_project_folder")!)
                        Hairline()
                        OptionRow(option: ConfigSchema.option("hide_file_names")!)
                    }
                }
            }

            Panel(padding: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Every other option").font(.studioHeadline)
                        Text("\(ConfigSchema.options.count) settings and \(ConfigSchema.mapSections.count) rule sections supported by wakatime-cli and the editor plugins.")
                            .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    Button("Open Advanced", action: showAdvanced).buttonStyle(.studioSecondary)
                }
            }
        }
    }
}

private struct APIURLRow: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let url = model.configuredAPIURL
        let endpoints = url.flatMap(HackatimeEndpoints.init(apiURL:))
        let isHackatime = url == ConfigSchema.hackatimeAPIURL
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("API URL").font(.studioBody.weight(.medium))
                KeyTag(key: "api_url")
                if endpoints?.looksLikeWakaTime == true {
                    Text("Points to WakaTime — heartbeats won’t reach Hackatime.").font(.studioCallout).foregroundStyle(Theme.error)
                } else if url == nil {
                    Text("Not set — wakatime-cli would default to WakaTime’s servers.").font(.studioCallout).foregroundStyle(Theme.warning)
                } else if !isHackatime {
                    Text("Custom server. Studio reads your stats from the same server.").font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(url ?? "Not set").font(.studioCode).foregroundStyle(url == nil ? Theme.inkTertiary : Theme.ink)
                    .textSelection(.enabled)
                if !isHackatime {
                    Button("Use Hackatime") { model.useHackatimeURL() }.buttonStyle(.studio(.secondary, compact: true))
                }
            }
        }
        .padding(.vertical, 10)
    }
}

private struct TrackingToggleRow: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Send heartbeats").font(.studioBody.weight(.medium))
                KeyTag(key: "disabled")
                Text("Pause tracking without uninstalling anything. Honoured by the VS Code extension; other editors may ignore it.")
                    .font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("Send heartbeats", isOn: Binding(
                get: { !model.trackingPaused },
                set: { model.set("disabled", $0 ? nil : "true") }))
                .toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 10)
    }
}

/// Shows the masked key, validates replacements against Hackatime before saving.
struct APIKeyEditor: View {
    @Environment(AppModel.self) private var model
    @State private var revealed = false
    @State private var editing = false
    @State private var draft = ""
    @State private var checking = false
    @State private var result: AppModel.KeyValidation?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("API key").font(.studioBody.weight(.medium))
                    KeyTag(key: "api_key")
                    connectionLine
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    switch model.keySource {
                    case .config(let key):
                        Text(revealed ? key : Redaction.mask(key))
                            .font(.studioCode).foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .accessibilityLabel(revealed ? "API key shown" : "API key, masked")
                        HStack(spacing: 4) {
                            Button(revealed ? "Hide" : "Reveal") { revealed.toggle() }.buttonStyle(.studio(.quiet, compact: true))
                            Button("Copy") { Pasteboard.copy(key); model.toast = Toast(message: "API key copied", style: .info) }
                                .buttonStyle(.studio(.quiet, compact: true))
                            Button("Replace…") { editing = true; draft = ""; result = nil }.buttonStyle(.studio(.secondary, compact: true))
                        }
                    case .vaultCommand, .environmentOnly, .missing:
                        Text("Not in config").font(.studioCode).foregroundStyle(Theme.inkTertiary)
                        Button("Add key…") { editing = true }.buttonStyle(.studio(.primary, compact: true))
                    }
                }
            }
            if editing { editor.transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .padding(.vertical, 10)
        .animation(Theme.Motion.appear, value: editing)
    }

    @ViewBuilder private var connectionLine: some View {
        switch model.connection {
        case .valid(let p):
            Label("Valid · @\(p.username ?? p.bestName)", systemImage: "checkmark.circle.fill").font(.studioCallout).foregroundStyle(Theme.ok)
        case .invalidKey:
            Label("Rejected by Hackatime — replace it below", systemImage: "xmark.octagon.fill").font(.studioCallout).foregroundStyle(Theme.error)
        case .failed(let e):
            Label(e.errorDescription ?? "Couldn’t verify", systemImage: "wifi.exclamationmark").font(.studioCallout).foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .checking, .unknown:
            Label("Checking…", systemImage: "clock").font(.studioCallout).foregroundStyle(Theme.inkTertiary)
        case .noKey:
            if case .vaultCommand = model.keySource {
                Text("Your key comes from api_key_vault_cmd, which Studio doesn’t run.").font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            } else if case .environmentOnly = model.keySource {
                Text("WAKATIME_API_KEY is set in your shell only.").font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            } else {
                Text("Required to send heartbeats and load stats.").font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var editor: some View {
        Well {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.apiKey == nil ? "Paste your Hackatime API key" : "Paste the new key. The current key stays until the new one is verified.")
                    .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                HStack(spacing: 8) {
                    SecureField("waka_…", text: $draft).textFieldStyle(.roundedBorder).font(.studioCode)
                        .onSubmit { Task { await verify() } }
                    Button("Paste") { draft = Pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                        .buttonStyle(.studio(.secondary, compact: true))
                    Button { Task { await verify() } } label: {
                        if checking { ProgressView().controlSize(.mini) } else { Text("Verify & save") }
                    }
                    .buttonStyle(.studio(.primary, compact: true))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                    Button("Cancel") { editing = false }.buttonStyle(.studio(.quiet, compact: true))
                }
                switch result {
                case .invalid:
                    StatusLine(status: .error, title: "Hackatime rejected this key", detail: "Nothing was saved. Copy it again from your Hackatime settings.")
                case .unreachable(let why):
                    HStack {
                        StatusLine(status: .warning, title: "Couldn’t verify", detail: why)
                        Spacer()
                        Button("Save without verifying") { save(profile: nil) }.buttonStyle(.studio(.secondary, compact: true))
                    }
                default: EmptyView()
                }
                Link("Where do I find my key?", destination: (model.endpoints?.root ?? URL(string: "https://hackatime.hackclub.com")!).appending(path: "my/settings"))
                    .font(.studioCaption)
            }
        }
    }

    private func verify() async {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        checking = true
        result = await model.check(key: key)
        checking = false
        if case .valid(let profile) = result { save(profile: profile) }
    }

    private func save(profile: UserProfile?) {
        if model.saveAPIKey(draft, profile: profile) {
            editing = false
            draft = ""
            revealed = false
        }
    }
}

// MARK: - Advanced

struct AdvancedConfigView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var category: ConfigOption.Category?

    private var filtered: [ConfigOption] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return ConfigSchema.options.filter { o in
            (category == nil || o.category == category) && (q.isEmpty || o.searchText.contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkTertiary)
                    TextField("Search options, keys or descriptions", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.inkTertiary)
                    }
                }
                .padding(.horizontal, 10).frame(height: 32)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous).strokeBorder(Theme.hairline))
                Picker("Category", selection: $category) {
                    Text("All categories").tag(ConfigOption.Category?.none)
                    ForEach(ConfigOption.Category.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag(Optional($0)) }
                }
                .labelsHidden().fixedSize()
            }

            ForEach(ConfigOption.Category.allCases) { cat in
                let options = filtered.filter { $0.category == cat }
                if !options.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: cat.rawValue)
                        Panel {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(options.enumerated()), id: \.element.id) { i, option in
                                    if option.key == "api_key" { APIKeyEditor() } else { OptionRow(option: option) }
                                    if i < options.count - 1 { Hairline() }
                                }
                            }
                        }
                    }
                }
            }

            let q = query.lowercased()
            let maps = ConfigSchema.mapSections.filter { q.isEmpty || "\($0.name) \($0.title) \($0.summary)".lowercased().contains(q) }
            if category == nil || category == .projects || category == .connection {
                ForEach(maps) { MapSectionEditor(section: $0) }
            }
            if q.isEmpty && category == nil { OtherKeysPanel() }
            if filtered.isEmpty && maps.isEmpty {
                Panel { UnavailableNote(symbol: "magnifyingglass", text: "No supported option matches “\(query)”.") }
            }
        }
    }
}

/// Editor for `pattern = value` sections ([projectmap], [project_api_key], [api_urls], …).
struct MapSectionEditor: View {
    var section: ConfigMapSection
    @Environment(AppModel.self) private var model
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var error: String?

    var body: some View {
        let entries = model.document?.effectiveEntries(in: section.name) ?? []
        let generated = Set(model.projectRules.rules.map(\.path))
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: section.title) { KeyTag(key: "[\(section.name)]", section: section.name) }
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.summary).font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    if section.name == ProjectRules.section {
                        Text("wakatime-cli loads these rules in no fixed order, so overlapping patterns are unpredictable. Folders & Projects writes non-overlapping rules for you.")
                            .font(.studioCaption).foregroundStyle(Theme.inkTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    if !entries.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { i, entry in
                                HStack(spacing: 10) {
                                    Text(entry.key).font(.studioCode).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
                                    Text(section.valueIsSecret ? Redaction.redactSecrets(in: maskValue(entry.value)) : entry.value)
                                        .font(.studioCode).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                                    Spacer()
                                    if section.name == ProjectRules.section, isGenerated(entry.key, generated) {
                                        Text("Folders & Projects").font(.studioCaption).foregroundStyle(Theme.accent)
                                    }
                                    Button { model.set(entry.key, nil, section: section.name) } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.plain).foregroundStyle(Theme.inkTertiary)
                                        .help("Remove rule").accessibilityLabel("Remove rule \(entry.key)")
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                if i < entries.count - 1 { Hairline() }
                            }
                        }
                        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous))
                    }
                    HStack(spacing: 6) {
                        TextField(section.keyLabel, text: $newKey).textFieldStyle(.roundedBorder).font(.studioCode)
                        if section.valueIsSecret {
                            SecureField(section.valueLabel, text: $newValue).textFieldStyle(.roundedBorder).font(.studioCode)
                        } else {
                            TextField(section.valueLabel, text: $newValue).textFieldStyle(.roundedBorder).font(.studioCode)
                        }
                        Button("Add", action: add).buttonStyle(.studio(.secondary, compact: true))
                            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let error { Text(error).font(.studioCaption).foregroundStyle(Theme.error) }
                }
            }
        }
    }

    private func isGenerated(_ key: String, _ paths: Set<String>) -> Bool {
        paths.contains { key.hasPrefix("^" + ProjectRules.escape($0) + "/") }
    }

    private func maskValue(_ value: String) -> String {
        if let pipe = value.firstIndex(of: "|") {
            return String(value[...pipe]) + Redaction.mask(String(value[value.index(after: pipe)...]))
        }
        return Redaction.mask(value)
    }

    private func add() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        let value = newValue.trimmingCharacters(in: .whitespaces)
        if key.contains("=") || key.contains(":") { error = "Patterns can’t contain “=” or “:” — the INI format uses them as separators."; return }
        if key.hasPrefix("#") || key.hasPrefix(";") || key.hasPrefix("[") { error = "Patterns can’t start with #, ; or [."; return }
        if (try? NSRegularExpression(pattern: key)) == nil { error = "That pattern isn’t a valid regular expression."; return }
        if let problem = INIValueRules.singleLineProblem(value) { error = problem; return }
        error = nil
        model.set(key, value, section: section.name)
        newKey = ""; newValue = ""
    }
}

/// Keys Studio doesn't have a schema entry for. They're shown and always preserved.
private struct OtherKeysPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let others = unknownEntries
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Other keys", subtitle: "Not recognised by Studio. They’re kept exactly as written.")
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(others, id: \.0) { id, section, key, value in
                            HStack(spacing: 10) {
                                Text("[\(section)]").font(.studioCode).foregroundStyle(Theme.inkTertiary)
                                Text(key).font(.studioCode).foregroundStyle(Theme.ink)
                                Text("=").font(.studioCode).foregroundStyle(Theme.inkTertiary)
                                Text(Redaction.redactSecrets(in: value.replacingOccurrences(of: "\n", with: " ⏎ ")))
                                    .font(.studioCode).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                                Spacer()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private var unknownEntries: [(String, String, String, String)] {
        guard let doc = model.document else { return [] }
        var out: [(String, String, String, String)] = []
        for section in doc.sectionNames {
            for entry in doc.effectiveEntries(in: section) where !ConfigSchema.isKnown(section: section, key: entry.key) {
                out.append(("\(section).\(entry.key)", section, entry.key, entry.value))
            }
        }
        return out
    }
}

// MARK: - File

struct ConfigFileView: View {
    @Environment(AppModel.self) private var model
    @State private var backups: [ConfigBackup] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Location")
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.location.displayPath).font(.studioCode).textSelection(.enabled)
                                Text("Chosen like wakatime-cli does: \(model.location.source.rawValue)\(model.environment.resolvedFromShell ? " · shell environment checked" : "")")
                                    .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            Button("Show in Finder") { model.perform(.reveal(model.location.url)) }.buttonStyle(.studio(.secondary, compact: true))
                            Button("Open in TextEdit") { openInTextEdit() }.buttonStyle(.studio(.secondary, compact: true))
                                .disabled(!model.location.exists)
                        }
                        if !model.location.editorsReadSameFile {
                            StatusLine(status: .warning, title: "VS Code reads a different file",
                                       detail: "The extension reads \(StudioPaths.abbreviate(model.location.editorPluginURL.path)).")
                        }
                        ForEach(model.document?.issues ?? []) { issue in
                            StatusLine(status: issue.severity == .error ? .error : .warning, title: "Line \(issue.lineNumber)", detail: issue.message)
                        }
                    }
                }
            }

            if let doc = model.document {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Contents", subtitle: "Read-only preview. Secrets are masked.")
                    Panel(padding: 0) {
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(previewLines(doc).enumerated()), id: \.offset) { i, line in
                                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                                        Text("\(i + 1)").font(.studioCode).foregroundStyle(Theme.inkTertiary).frame(width: 28, alignment: .trailing)
                                        Text(line.isEmpty ? " " : line).font(.studioCode).foregroundStyle(color(for: line))
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                            .padding(16)
                            .textSelection(.enabled)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Backups", subtitle: "Studio saves a copy before every change (last \(ConfigStore.maxBackups) kept).") {
                    Button("Show folder") { model.perform(.reveal(StudioPaths.backupsDirectory)) }.buttonStyle(.studioQuiet)
                }
                Panel {
                    if backups.isEmpty {
                        UnavailableNote(symbol: "clock.arrow.circlepath", text: "No backups yet. One is created the first time Studio changes an existing file.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(backups.prefix(8).enumerated()), id: \.element.id) { i, backup in
                                HStack {
                                    Text(backup.created.formatted(date: .abbreviated, time: .standard)).font(.studioBody)
                                    Text(Formatters.relative(backup.created)).font(.studioCaption).foregroundStyle(Theme.inkTertiary)
                                    Spacer()
                                    Button("Restore") { model.restore(backup); reloadBackups() }.buttonStyle(.studio(.secondary, compact: true))
                                }
                                .padding(.vertical, 7)
                                if i < min(backups.count, 8) - 1 { Hairline() }
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: reloadBackups)
        .onChange(of: model.document) { _, _ in reloadBackups() }
    }

    private func reloadBackups() { backups = ConfigStore.backups() }

    private func previewLines(_ doc: INIDocument) -> [String] {
        let secretSections: Set<String> = ["project_api_key", "api_urls"]
        var current = ""
        return doc.serialized().components(separatedBy: "\n").dropLast(doc.serialized().hasSuffix("\n") ? 1 : 0).map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("["), let close = t.firstIndex(of: "]") { current = String(t[t.index(after: t.startIndex)..<close]).lowercased() }
            if let eq = line.firstIndex(of: "=") {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                if key == "api_key" || key == "apikey" || secretSections.contains(current) {
                    let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    let masked = current == "api_urls" ? Redaction.redactSecrets(in: value) : Redaction.mask(value)
                    return String(line[...eq]) + " " + masked
                }
            }
            return Redaction.redactSecrets(in: line)
        }
    }

    private func color(for line: String) -> Color {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") || t.hasPrefix(";") { return Theme.inkTertiary }
        if t.hasPrefix("[") { return Theme.accent }
        return Theme.ink
    }

    private func openInTextEdit() {
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([model.location.url.resolvingSymlinksInPath()], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}
