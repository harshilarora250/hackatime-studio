import Foundation

/// Resolves which `.wakatime.cfg` the tracking tools actually use, following wakatime-cli's
/// lookup order (USAGE.md → "Config File") and what the VS Code extensions read.
nonisolated struct ConfigLocation: Equatable, Sendable {
    enum Source: String, Sendable {
        case wakatimeHome = "$WAKATIME_HOME/.wakatime.cfg"
        case home = "~/.wakatime.cfg"
        case xdg = "XDG config"
    }

    /// The file wakatime-cli reads (or the file Studio will create).
    var url: URL
    var source: Source
    var exists: Bool
    /// The file VS Code extensions read. Differs from `url` only in the XDG case.
    var editorPluginURL: URL
    /// Other config files found that are *not* in use (shadowed).
    var shadowed: [URL]

    var editorsReadSameFile: Bool { url.standardizedFileURL == editorPluginURL.standardizedFileURL }
    var displayPath: String { StudioPaths.abbreviate(url.path) }
}

nonisolated enum ConfigLocator {

    static func locate(environment: ShellEnvironment,
                       home: URL = StudioPaths.home,
                       fileManager: FileManager = .default) -> ConfigLocation {
        func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }
        func isDirectory(_ path: String) -> Bool {
            var dir: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
        }

        let homeFile = home.appending(path: ".wakatime.cfg")
        let xdgBase: URL = {
            if let x = environment.xdgConfigHome, x.hasPrefix("/") { return URL(fileURLWithPath: x, isDirectory: true) }
            return home.appending(path: ".config", directoryHint: .isDirectory)
        }()
        let xdgFile = xdgBase.appending(path: "wakatime/wakatime.cfg")

        var wakatimeHomeFile: URL?
        if let wh = environment.wakatimeHome {
            let expanded = StudioPaths.expandTilde(wh)
            if isDirectory(expanded) {
                wakatimeHomeFile = URL(fileURLWithPath: expanded, isDirectory: true).appending(path: ".wakatime.cfg")
            }
        }
        // VS Code extensions: path.join(WAKATIME_HOME || HOME, '.wakatime.cfg')
        let pluginFile = wakatimeHomeFile ?? homeFile

        let all = [wakatimeHomeFile, homeFile, xdgFile].compactMap { $0 }
        func shadowed(except chosen: URL) -> [URL] {
            all.filter { $0 != chosen && exists($0) }
        }

        if let whf = wakatimeHomeFile {
            return ConfigLocation(url: whf, source: .wakatimeHome, exists: exists(whf),
                                  editorPluginURL: pluginFile, shadowed: shadowed(except: whf))
        }
        if exists(homeFile) {
            return ConfigLocation(url: homeFile, source: .home, exists: true,
                                  editorPluginURL: pluginFile, shadowed: shadowed(except: homeFile))
        }
        if exists(xdgFile) {
            return ConfigLocation(url: xdgFile, source: .xdg, exists: true,
                                  editorPluginURL: pluginFile, shadowed: shadowed(except: xdgFile))
        }
        // Nothing exists: create ~/.wakatime.cfg, the file both the CLI and the editor plugins read.
        return ConfigLocation(url: homeFile, source: .home, exists: false,
                              editorPluginURL: pluginFile, shadowed: [])
    }
}
