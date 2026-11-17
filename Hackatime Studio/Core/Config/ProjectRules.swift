import Foundation

/// How a folder should be interpreted by wakatime-cli.
nonisolated enum FolderMode: Hashable, Sendable, Codable {
    /// No rule: wakatime-cli's normal detection (.wakatime-project → git → editor workspace).
    case automatic
    /// Container folder: every direct sub-folder is its own project, named after the sub-folder.
    case eachSubfolder
    /// The whole folder (and everything below it) is one project with this name.
    case singleProject(String)
    /// Never track anything inside this folder.
    case excluded

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .eachSubfolder: "Each sub-folder is a project"
        case .singleProject: "One project"
        case .excluded: "Excluded"
        }
    }
}

nonisolated struct FolderRule: Identifiable, Hashable, Sendable {
    var path: String
    var mode: FolderMode
    var id: String { path.lowercased() }
    var name: String { (path as NSString).lastPathComponent }
}

/// A `[projectmap]` entry Studio did not generate. Preserved and shown as-is.
nonisolated struct RawMapEntry: Hashable, Sendable, Identifiable {
    var key: String
    var value: String
    var id: String { key }
}

nonisolated struct ParsedProjectRules: Equatable, Sendable {
    /// Rules recognised from Studio-generated projectmap/exclude entries.
    var rules: [FolderRule]
    /// projectmap entries that don't follow Studio's pattern (left untouched).
    var customMapEntries: [RawMapEntry]
    /// exclude patterns that aren't simple folder exclusions (left untouched).
    var customExcludes: [String]
    /// `exclude = true` means *everything* is excluded; Studio won't add folder patterns then.
    var excludeIsTrue: Bool
    /// Patterns also read from the legacy `ignore` key.
    var legacyIgnore: [String]
}

nonisolated enum ProjectRulesError: LocalizedError, Equatable {
    case unsupportedCharacters(path: String)
    case invalidProjectName(String)
    case excludeIsTrue

    var errorDescription: String? {
        switch self {
        case .unsupportedCharacters(let p):
            "“\(StudioPaths.abbreviate(p))” contains “=” or “:”, which the INI format uses as a separator. wakatime-cli can’t read a project-map rule for this path."
        case .invalidProjectName(let n):
            "The project name “\(n)” contains “#” or “;”, which wakatime-cli would treat as the start of a comment."
        case .excludeIsTrue:
            "Your config has exclude = true, which already excludes everything. Change it in Advanced → Tracking scope first."
        }
    }
}

nonisolated enum ProjectRules {

    static let section = "projectmap"
    private static let subfolderCapture = "([^/]+)/"

    // MARK: Regex helpers

    static func escape(_ path: String) -> String {
        let special = Set("\\.+*?()|[]{}^$")
        var out = ""
        for ch in path {
            if special.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Reverses `escape`. Returns nil when the string contains unescaped regex syntax.
    static func unescape(_ pattern: String) -> String? {
        let special = Set("\\.+*?()|[]{}^$")
        var out = ""
        var escaping = false
        for ch in pattern {
            if escaping {
                guard special.contains(ch) else { return nil }
                out.append(ch); escaping = false
            } else if ch == "\\" {
                escaping = true
            } else if special.contains(ch) {
                return nil
            } else {
                out.append(ch)
            }
        }
        return escaping ? nil : out
    }

    static func normalize(_ path: String) -> String {
        var p = (StudioPaths.expandTilde(path) as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    // MARK: Generated patterns

    /// `^/abs/path/` + one look-ahead per nested rule + optional sub-folder capture.
    static func projectMapKey(for rule: FolderRule, nested: [String]) -> String {
        var key = "^" + escape(rule.path) + "/"
        let relative = nested.compactMap { child -> String? in
            guard child.lowercased().hasPrefix(rule.path.lowercased() + "/") else { return nil }
            return escape(String(child.dropFirst(rule.path.count + 1)))
        }.sorted()
        // One look-ahead per nested rule. No "(?:" groups: go-ini treats ":" as a key delimiter.
        key += relative.map { "(?!" + $0 + "/)" }.joined()
        if rule.mode == .eachSubfolder { key += subfolderCapture }
        return key
    }

    static func excludePattern(for path: String) -> String { "^" + escape(path) + "/" }

    // MARK: Parsing

    static func parse(_ document: INIDocument) -> ParsedProjectRules {
        var rules: [FolderRule] = []
        var custom: [RawMapEntry] = []

        for entry in document.effectiveEntries(in: section) {
            if let rule = recognise(key: entry.key, value: entry.value) {
                rules.append(rule)
            } else {
                custom.append(RawMapEntry(key: entry.key, value: entry.value))
            }
        }

        let excludeRaw = document.value(section: "settings", key: "exclude") ?? ""
        let excludeIsTrue = excludeRaw.trimmingCharacters(in: .whitespaces).lowercased() == "true"
        var customExcludes: [String] = []
        if !excludeIsTrue {
            for item in listItems(excludeRaw) {
                if item.lowercased() == "false" { continue }
                if item.hasPrefix("^"), item.hasSuffix("/"),
                   let path = unescape(String(item.dropFirst().dropLast())), path.hasPrefix("/") {
                    if !rules.contains(where: { $0.id == path.lowercased() }) {
                        rules.append(FolderRule(path: path, mode: .excluded))
                    }
                } else {
                    customExcludes.append(item)
                }
            }
        }
        let legacy = listItems(document.value(section: "settings", key: "ignore") ?? "")
        return ParsedProjectRules(rules: rules, customMapEntries: custom, customExcludes: customExcludes,
                                  excludeIsTrue: excludeIsTrue, legacyIgnore: legacy)
    }

    private static func recognise(key: String, value: String) -> FolderRule? {
        guard key.hasPrefix("^") else { return nil }
        var body = String(key.dropFirst())
        var each = false
        if body.hasSuffix("/" + subfolderCapture) || body.hasSuffix(")" + subfolderCapture) {
            each = true
            body.removeLast(subfolderCapture.count)
        }
        // Optional look-aheads "(?!a/)(?!b/)" directly after the folder's trailing slash.
        // An escaped path can never contain an unescaped "/(?!", so the first one marks the end.
        if let start = body.range(of: "/(?!") {
            let tail = body[start.upperBound...]
            guard tail.hasSuffix("/)") else { return nil }
            body = String(body[..<start.lowerBound]) + "/"
        }
        guard body.hasSuffix("/"), let path = unescape(String(body.dropLast())), path.hasPrefix("/") else { return nil }
        if each {
            guard value.trimmingCharacters(in: .whitespaces) == "{0}" else { return nil }
            return FolderRule(path: path, mode: .eachSubfolder)
        }
        return FolderRule(path: path, mode: .singleProject(value))
    }

    static func listItems(_ raw: String) -> [String] {
        raw.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Writing

    static func validate(_ rules: [FolderRule]) throws {
        for rule in rules {
            if rule.path.contains("=") || rule.path.contains(":") {
                throw ProjectRulesError.unsupportedCharacters(path: rule.path)
            }
            if case .singleProject(let name) = rule.mode, name.contains("#") || name.contains(";") {
                throw ProjectRulesError.invalidProjectName(name)
            }
        }
    }

    /// Computes the minimal config edits that turn `current` into `rules`.
    /// Custom projectmap entries and custom exclude patterns are never touched.
    static func edits(from document: INIDocument, to newRules: [FolderRule]) throws -> [ConfigEdit] {
        try validate(newRules)
        let current = parse(document)
        var edits: [ConfigEdit] = []

        // projectmap ---------------------------------------------------------------------
        let mapRules = newRules.filter {
            if case .singleProject = $0.mode { return true }
            return $0.mode == .eachSubfolder
        }
        var desired: [String: String] = [:]
        for rule in mapRules {
            let nested = mapRules.filter { $0.id != rule.id }.map(\.path)
            let key = projectMapKey(for: rule, nested: nested)
            if case .singleProject(let name) = rule.mode {
                desired[key] = name.trimmingCharacters(in: .whitespaces).isEmpty ? rule.name : name
            } else {
                desired[key] = "{0}"
            }
        }
        let existingGenerated = document.effectiveEntries(in: section)
            .filter { recognise(key: $0.key, value: $0.value) != nil }
        for entry in existingGenerated where desired[entry.key] == nil {
            edits.append(.set(section: section, key: entry.key, value: nil))
        }
        for (key, value) in desired.sorted(by: { $0.key < $1.key }) {
            if document.entry(section: section, key: key)?.value != value {
                edits.append(.set(section: section, key: key, value: value))
            }
        }

        // exclude ------------------------------------------------------------------------
        let wantedExcludes = newRules.filter { $0.mode == .excluded }.map { excludePattern(for: $0.path) }
        let currentGenerated = current.rules.filter { $0.mode == .excluded }.map { excludePattern(for: $0.path) }
        if current.excludeIsTrue {
            if !wantedExcludes.isEmpty && Set(wantedExcludes) != Set(currentGenerated) { throw ProjectRulesError.excludeIsTrue }
            return edits
        }
        let raw = document.value(section: "settings", key: "exclude") ?? ""
        var items = listItems(raw).filter { $0.lowercased() != "false" }
        let wantedSet = Set(wantedExcludes.map { $0.lowercased() })
        let generatedSet = Set(currentGenerated.map { $0.lowercased() })
        items.removeAll { generatedSet.contains($0.lowercased()) && !wantedSet.contains($0.lowercased()) }
        for pattern in wantedExcludes where !items.contains(where: { $0.lowercased() == pattern.lowercased() }) {
            items.append(pattern)
        }
        let newValue: String? = items.isEmpty ? nil : items.joined(separator: "\n") + (items.count == 1 ? "\n" : "")
        let normalizedOld = listItems(raw).filter { $0.lowercased() != "false" }
        if items != normalizedOld {
            edits.append(.settings("exclude", newValue))
        }
        return edits
    }
}
