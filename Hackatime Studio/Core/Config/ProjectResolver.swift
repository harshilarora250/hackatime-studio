import Foundation

/// Predicts the project name wakatime-cli will report for files inside a folder, using the same
/// priority order the CLI uses (pkg/project): `.wakatime-project` (searched upwards) →
/// `[projectmap]` → git repository → editor workspace. Used to preview folder rules.
nonisolated struct FolderInsight: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case projectFile(URL)
        case projectMap(pattern: String)
        case git(root: URL)
        case editorWorkspace
        case excluded(pattern: String)
        case notTracked(reason: String)
    }

    var url: URL
    var projectName: String?
    var source: Source
    var isGitRepository: Bool
    var hasProjectFile: Bool
    var hasLocalConfig: Bool
    /// More than one projectmap pattern matches — wakatime-cli picks one unpredictably.
    var ambiguousPatterns: [String]
    var id: URL { url }
    var name: String { url.lastPathComponent }

    var explanation: String {
        switch source {
        case .projectFile(let f): "From \(StudioPaths.abbreviate(f.path))"
        case .projectMap: "From a [projectmap] rule"
        case .git(let root): root.lastPathComponent == name ? "Git repository" : "Inside git repo “\(root.lastPathComponent)”"
        case .editorWorkspace: "Named after the folder you open in VS Code"
        case .excluded: "Excluded — not tracked"
        case .notTracked(let reason): reason
        }
    }
}

nonisolated enum ProjectResolver {

    static func insight(for folder: URL, document: INIDocument, fileManager: FileManager = .default) -> FolderInsight {
        let samplePath = folder.path + "/__sample__.txt"
        let gitRoot = findUp(".git", from: folder, fileManager: fileManager)?.deletingLastPathComponent()
        let projectFile = findUp(".wakatime-project", from: folder, fileManager: fileManager)
        let hasLocalConfig = fileManager.fileExists(atPath: folder.appending(path: ".wakatime").path)

        func make(_ name: String?, _ source: FolderInsight.Source, ambiguous: [String] = []) -> FolderInsight {
            FolderInsight(url: folder, projectName: name, source: source,
                          isGitRepository: gitRoot?.standardizedFileURL == folder.standardizedFileURL,
                          hasProjectFile: projectFile?.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
                          hasLocalConfig: hasLocalConfig, ambiguousPatterns: ambiguous)
        }

        // Exclusions are applied before project detection.
        let settings = "settings"
        let excludes = ProjectRules.listItems(document.value(section: settings, key: "exclude") ?? "")
            + ProjectRules.listItems(document.value(section: settings, key: "ignore") ?? "")
        let includes = ProjectRules.listItems(document.value(section: settings, key: "include") ?? "")
        if let hit = firstMatch(excludes, samplePath), firstMatch(includes, samplePath) == nil {
            return make(nil, .excluded(pattern: hit))
        }

        let onlyWithFile = (document.value(section: settings, key: "include_only_with_project_file") ?? "").lowercased() == "true"
        if onlyWithFile && projectFile == nil {
            return make(nil, .notTracked(reason: "No .wakatime-project file (required by include_only_with_project_file)"))
        }

        if let projectFile {
            let dir = projectFile.deletingLastPathComponent().lastPathComponent
            let firstLine = (try? String(contentsOf: projectFile, encoding: .utf8))?
                .components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = firstLine.isEmpty ? dir : firstLine.replacingOccurrences(of: "{project}", with: dir)
            return make(name, .projectFile(projectFile))
        }

        let matches = document.effectiveEntries(in: ProjectRules.section).compactMap { entry -> (String, String)? in
            guard let name = apply(pattern: entry.key, template: entry.value, to: samplePath) else { return nil }
            return (entry.key, name)
        }
        if let first = matches.first {
            let distinct = Set(matches.map { $0.1 })
            return make(first.1, .projectMap(pattern: first.0),
                        ambiguous: distinct.count > 1 ? matches.map(\.0) : [])
        }

        if let gitRoot {
            return make(gitRoot.lastPathComponent, .git(root: gitRoot))
        }
        return make(nil, .editorWorkspace)
    }

    static func children(of folder: URL, fileManager: FileManager = .default) -> [URL] {
        let items = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                          options: [.skipsHiddenFiles])) ?? []
        return items.filter {
            let v = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return v?.isDirectory == true && v?.isPackage != true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Helpers

    static func findUp(_ name: String, from folder: URL, fileManager: FileManager) -> URL? {
        var dir = folder.standardizedFileURL
        for _ in 0..<500 {
            let candidate = dir.appending(path: name)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path || dir.path == "/" { return nil }
            dir = parent
        }
        return nil
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        let p = pattern.hasPrefix("(?i)") ? pattern : "(?i)" + pattern
        return try? NSRegularExpression(pattern: p)
    }

    private static func firstMatch(_ patterns: [String], _ path: String) -> String? {
        patterns.first { p in
            guard p.lowercased() != "false" else { return false }
            if p.lowercased() == "true" { return true }
            guard let r = regex(p) else { return false }
            return r.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
        }
    }

    /// Applies a projectmap pattern; `{0}`, `{1}` … are replaced by capture groups (pyfmt).
    static func apply(pattern: String, template: String, to path: String) -> String? {
        guard let r = regex(pattern),
              let m = r.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) else { return nil }
        var result = template
        for i in 1..<max(m.numberOfRanges, 1) {
            let range = m.range(at: i)
            let value = range.location == NSNotFound ? "" : (path as NSString).substring(with: range)
            result = result.replacingOccurrences(of: "{\(i - 1)}", with: value)
        }
        return result
    }
}
