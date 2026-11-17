import SwiftUI

struct EditorsView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingRemoval: KnownExtension?

    var body: some View {
        Page {
            PageHeader(title: "Editors", subtitle: "Install and verify the extension that sends your coding activity to Hackatime.") {
                Button { Task { await model.refreshEditors() } } label: { Label("Recheck", systemImage: "arrow.clockwise") }
                    .buttonStyle(.studioSecondary)
            }
            VSCodePanel(pendingRemoval: $pendingRemoval)
            OtherEditorsPanel()
        }
        .confirmationDialog("Remove \(pendingRemoval?.name ?? "")?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            presenting: pendingRemoval) { ext in
            Button("Uninstall from VS Code", role: .destructive) { Task { await model.uninstall(ext) } }
            Button("Cancel", role: .cancel) {}
        } message: { ext in
            Text("Studio will run `code --uninstall-extension \(ext.id)`. Your config file and other extensions are not touched.")
        }
    }
}

private struct VSCodePanel: View {
    @Binding var pendingRemoval: KnownExtension?
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.vscodeStatus
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Visual Studio Code")
            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accentSoft)
                            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                        }
                        .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Visual Studio Code").font(.studioHeadline)
                            if let status {
                                if status.isAppInstalled {
                                    Text("Version \(status.appVersion ?? "?")\(status.isRunning ? " · running" : "") · \(StudioPaths.abbreviate(status.appURL!.path))")
                                        .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                                } else {
                                    Text("Not installed").font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                                }
                            } else {
                                Text("Checking…").font(.studioCallout).foregroundStyle(Theme.inkTertiary)
                            }
                        }
                        Spacer()
                        if let status, !status.isAppInstalled {
                            Link(destination: URL(string: "https://code.visualstudio.com")!) { Text("Get VS Code") }
                                .buttonStyle(.studioPrimary)
                        }
                    }

                    if let status, status.isAppInstalled {
                        Hairline()
                        verification(status)
                        Hairline()
                        VStack(spacing: 0) {
                            ForEach(model.vscode.knownExtensions.filter { $0.role != .unofficial || status.isInstalled($0.id) }) { ext in
                                ExtensionRow(ext: ext, status: status, pendingRemoval: $pendingRemoval)
                            }
                        }
                        if status.cliURL == nil {
                            StatusLine(status: .warning, title: "VS Code’s command-line tool wasn’t found",
                                       detail: "Studio can’t install extensions automatically. Use “Open in VS Code” and click Install there.")
                        }
                        if let error = status.detectionError {
                            StatusLine(status: .warning, title: "Detection problem", detail: error)
                        }
                        manualSteps
                    }
                }
            }
        }
    }

    @ViewBuilder private func verification(_ status: EditorStatus) -> some View {
        let trackers = model.vscode.knownExtensions.filter { $0.role != .unofficial && status.isInstalled($0.id) }
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Status")
            StatusLine(status: trackers.isEmpty ? .error : .ok,
                       title: trackers.isEmpty ? "Extension not installed" : "Extension installed",
                       detail: trackers.isEmpty ? "Install Hackatime Time Tracker below." : trackers.map(\.name).joined(separator: ", ") + " · detected via \(status.detectionSource)")
            StatusLine(status: model.location.exists && model.apiKey != nil ? .ok : .error,
                       title: model.location.exists && model.apiKey != nil ? "Config ready" : "Config incomplete",
                       detail: model.location.editorsReadSameFile
                       ? "The extension reads \(StudioPaths.abbreviate(model.location.editorPluginURL.path))."
                       : "The extension reads \(StudioPaths.abbreviate(model.location.editorPluginURL.path)), not \(model.location.displayPath).")
            heartbeatLine
            if trackers.count > 1 {
                StatusLine(status: .warning, title: "Two tracking extensions installed",
                           detail: "Both will send heartbeats. Keep one — Hackatime Time Tracker is recommended.")
            }
        }
    }

    @ViewBuilder private var heartbeatLine: some View {
        if !model.connection.isValid {
            StatusLine(status: .unknown, title: "Tracking not verified", detail: "Needs a working API connection to check.")
        } else if let latest = model.latestVSCode {
            if latest.hasHeartbeat, let time = latest.heartbeat?.time {
                StatusLine(status: Date().timeIntervalSince(time) < 86400 ? .ok : .info, title: "Hackatime has received VS Code heartbeats",
                           detail: "Last one \(Formatters.relative(time))\(latest.heartbeat?.project.map { " in \($0)" } ?? "").")
            } else {
                StatusLine(status: .warning, title: "No VS Code heartbeats yet",
                           detail: "After installing, reload VS Code, open a project and edit a file for a minute, then Recheck.")
            }
        } else if let error = model.activityError {
            StatusLine(status: .unknown, title: "Couldn’t check heartbeats", detail: error)
        } else {
            StatusLine(status: .unknown, title: "Checking heartbeats…", detail: nil)
        }
    }

    private var manualSteps: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open VS Code and click the Extensions icon (⇧⌘X).")
                Text("2. Search for “Hackatime”.")
                Text("3. Install “Hackatime Time Tracker” by Hack Club. Don’t install the extension named just “Hackatime” — it’s unofficial.")
                Text("4. Reload extensions if VS Code asks. It uses the API key Studio saved in your config.")
                Link("Hackatime’s VS Code guide", destination: model.vscode.setupDocsURL)
            }
            .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            .padding(.top, 6)
        } label: {
            Text("Install manually instead").font(.studioCallout.weight(.medium))
        }
    }
}

private struct ExtensionRow: View {
    var ext: KnownExtension
    var status: EditorStatus
    @Binding var pendingRemoval: KnownExtension?
    @Environment(AppModel.self) private var model

    var body: some View {
        let installed = status.isInstalled(ext.id)
        let busy = model.editorBusy == ext.id
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(ext.name).font(.studioBody.weight(.medium))
                    roleBadge
                }
                HStack(spacing: 6) {
                    Text(ext.id).font(.studioCode).foregroundStyle(Theme.inkTertiary)
                    Text(installed ? "· v\(status.version(of: ext.id) ?? "?") installed" : "· not installed")
                        .font(.studioCaption).foregroundStyle(installed ? Theme.ok : Theme.inkTertiary)
                }
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
                Text(installed ? "Removing…" : "Installing…").font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            } else {
                Button("Open in VS Code") { model.vscode.openExtensionPage(ext) }.buttonStyle(.studio(.quiet, compact: true))
                if installed {
                    Button("Uninstall") { pendingRemoval = ext }.buttonStyle(.studio(.destructive, compact: true))
                } else if ext.role != .unofficial {
                    Button("Install") { Task { await model.install(ext) } }
                        .buttonStyle(.studio(ext.role == .recommended ? .primary : .secondary, compact: true))
                        .disabled(status.cliURL == nil || model.editorBusy != nil)
                        .help("Runs `code --install-extension \(ext.id)`")
                }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder private var roleBadge: some View {
        let (text, color): (String, Color) = switch ext.role {
        case .recommended: ("Recommended", Theme.accent)
        case .compatible: ("Compatible", Theme.inkSecondary)
        case .unofficial: ("Unofficial", Theme.warning)
        }
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct OtherEditorsPanel: View {
    private let editors: [(String, String)] = [
        ("Cursor", "cursor"), ("Windsurf", "windsurf"), ("Xcode", "xcode"), ("JetBrains IDEs", "intellij-idea"),
        ("Zed", "zed"), ("Neovim", "neovim"), ("Sublime Text", "sublime-text"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Other editors", subtitle: "Not managed by Studio yet. They read the same config, so your settings already apply once their plugin is installed.")
            Panel {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(editors, id: \.0) { name, slug in
                        Link(destination: URL(string: "https://hackatime.hackclub.com/docs/editors/\(slug)")!) {
                            HStack {
                                Text(name).font(.studioBody).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkTertiary)
                            }
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Open Hackatime’s setup guide for \(name)")
                    }
                }
            }
        }
    }
}
