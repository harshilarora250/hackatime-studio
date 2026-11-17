import Foundation

nonisolated enum UninstallMode: String, CaseIterable, Identifiable, Sendable {
    case studioManaged, everything
    var id: String { rawValue }
    var title: String {
        switch self {
        case .studioManaged: "Remove what Studio set up"
        case .everything: "Remove Hackatime / WakaTime completely"
        }
    }
    var summary: String {
        switch self {
        case .studioManaged: "Undo Studio’s own changes: extensions it installed, settings it added, and folder rules it wrote. Anything you set up before Studio stays."
        case .everything: "Remove every detected tracking extension, the config file and the ~/.wakatime folder (wakatime-cli, logs, offline queue). Hackatime Studio itself stays installed."
        }
    }
}

nonisolated struct UninstallItem: Identifiable, Hashable, Sendable {
    enum Action: Hashable, Sendable {
        case uninstallExtension(id: String)
        case removeConfigKeys([ConfigKeyRef])
        case trashConfigFile(URL)
        case trashDirectory(URL)
        /// Shown for transparency; Studio can't (or shouldn't) do it automatically.
        case manual
    }

    var id: String
    var title: String
    var detail: String
    var action: Action
    var isSelected: Bool = true
    var isRemovable: Bool { action != .manual }
}

nonisolated struct ConfigKeyRef: Hashable, Sendable {
    var section: String
    var key: String
}

nonisolated struct UninstallPlan: Equatable, Sendable {
    var mode: UninstallMode
    var items: [UninstallItem]
    var warnings: [String]
    var isEmpty: Bool { !items.contains(where: \.isRemovable) }
}

nonisolated struct UninstallOutcome: Identifiable, Sendable {
    var id: String
    var title: String
    var succeeded: Bool
    var message: String
}

nonisolated enum UninstallPlanner {

    static func plan(mode: UninstallMode,
                     ledger: StudioLedger,
                     location: ConfigLocation,
                     document: INIDocument?,
                     vscode: EditorStatus?,
                     knownExtensions: [KnownExtension],
                     installation: WakatimeInstallation?) -> UninstallPlan {
        var items: [UninstallItem] = []
        var warnings: [String] = []

        switch mode {
        case .studioManaged:
            for ext in knownExtensions where ledger.installedExtensions.contains(ext.id.lowercased()) && vscode?.isInstalled(ext.id) == true {
                items.append(.init(id: "ext.\(ext.id)", title: "Uninstall \(ext.name) from VS Code",
                                   detail: "Installed by Studio. Runs `code --uninstall-extension \(ext.id)`.",
                                   action: .uninstallExtension(id: ext.id)))
            }
            let createdByStudio = ledger.createdConfigPath == location.url.path && location.exists
            if createdByStudio {
                items.append(.init(id: "cfg.file", title: "Delete \(location.displayPath)",
                                   detail: "Studio created this file during setup. It’s backed up to Studio’s Backups folder, then moved to the Trash.",
                                   action: .trashConfigFile(location.url)))
            } else if let document {
                // Only keys the ledger says Studio created, and that still exist. `exclude` is shared
                // with the user's own patterns, so it's never removed wholesale.
                var refs: [ConfigKeyRef] = []
                for entry in ledger.addedKeys(for: location.url.path).sorted() {
                    let parts = entry.split(separator: ".", maxSplits: 1).map(String.init)
                    guard parts.count == 2, entry != "settings.exclude",
                          document.entry(section: parts[0], key: parts[1]) != nil else { continue }
                    refs.append(ConfigKeyRef(section: parts[0], key: parts[1]))
                }
                let rules = ProjectRules.parse(document)
                if !refs.isEmpty {
                    let names = refs.map { $0.section == "settings" ? $0.key : "[\($0.section)] \($0.key)" }
                    items.append(.init(id: "cfg.keys", title: "Remove \(refs.count) setting(s) Studio added",
                                       detail: names.joined(separator: "\n") + "\nThe file is backed up first; everything else in it is kept.",
                                       action: .removeConfigKeys(refs)))
                }
                let excluded = rules.rules.filter { $0.mode == .excluded }
                if !excluded.isEmpty {
                    items.append(.init(id: "cfg.excludes", title: "Folder exclusions stay",
                                       detail: "Excluded folders are stored in your exclude list together with your own patterns, so they’re left in place. Remove them in Folders & Projects if you want.",
                                       action: .manual))
                }
            }
            if items.isEmpty {
                warnings.append("Studio hasn’t installed or added anything that’s still present.")
            }

        case .everything:
            for ext in knownExtensions where vscode?.isInstalled(ext.id) == true {
                items.append(.init(id: "ext.\(ext.id)", title: "Uninstall \(ext.name) from VS Code",
                                   detail: "v\(vscode?.version(of: ext.id) ?? "?") · runs `code --uninstall-extension \(ext.id)`.",
                                   action: .uninstallExtension(id: ext.id)))
            }
            if location.exists {
                items.append(.init(id: "cfg.file", title: "Delete \(location.displayPath)",
                                   detail: "Contains your API key and all tracking settings. Backed up to Studio’s Backups folder, then moved to the Trash.",
                                   action: .trashConfigFile(location.url)))
            }
            for other in location.shadowed {
                items.append(.init(id: "cfg.shadow.\(other.path)", title: "Delete \(StudioPaths.abbreviate(other.path))",
                                   detail: "Another (unused) WakaTime config file. Backed up, then moved to the Trash.",
                                   action: .trashConfigFile(other), isSelected: false))
            }
            if let inst = installation, inst.resourcesDirectoryExists {
                let contents = inst.resourceItems.map(\.lastPathComponent).sorted().prefix(8).joined(separator: ", ")
                items.append(.init(id: "res.dir", title: "Move \(StudioPaths.abbreviate(inst.resourcesDirectory.path)) to the Trash",
                                   detail: "wakatime-cli, logs, internal state and the offline queue. Contains: \(contents.isEmpty ? "nothing" : contents)",
                                   action: .trashDirectory(inst.resourcesDirectory)))
                if let count = inst.offlineQueueCount, count > 0 {
                    warnings.append("\(count) heartbeat(s) in the offline queue haven’t been sent to Hackatime yet. Removing ~/.wakatime discards them.")
                }
            }
            if let global = installation?.globalCLI {
                items.append(.init(id: "cli.global", title: "Global wakatime-cli at \(global.path)",
                                   detail: "Installed outside the editor extensions (e.g. Homebrew). Remove it with the tool that installed it, e.g. `brew uninstall wakatime-cli`.",
                                   action: .manual))
            }
            items.append(.init(id: "other.editors", title: "Plugins in other editors",
                               detail: "Studio V1 only detects VS Code. Remove WakaTime/Hackatime plugins from other editors (JetBrains, Zed, Neovim…) inside those editors.",
                               action: .manual))
            if vscode?.isRunning == true {
                warnings.append("VS Code is running. Reload its window after removal so the extension stops.")
            }
        }
        return UninstallPlan(mode: mode, items: items, warnings: warnings)
    }
}
