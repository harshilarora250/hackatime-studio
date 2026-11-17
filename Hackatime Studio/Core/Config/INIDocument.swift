import Foundation

/// A lossless, line-preserving model of a `.wakatime.cfg` file.
///
/// The parsing rules mirror what wakatime-cli actually does (go-ini v1 with
/// `AllowPythonMultilineValues`, keys/sections matched case-insensitively by viper):
/// * `#` / `;` lines are comments.
/// * `[name]` starts a section. A `[` line without `]` is dropped by wakatime-cli.
/// * The first `=` or `:` separates key and value.
/// * A key with an empty value followed by indented lines is a multi-line (list) value.
/// * In an unquoted single-line value, the first `#` or `;` starts an inline comment.
///
/// Every line that Studio does not explicitly change is written back byte-for-byte.
nonisolated struct INIDocument: Equatable, Sendable {

    struct Entry: Equatable, Sendable {
        /// Key exactly as written in the file.
        var key: String
        /// Effective value as wakatime-cli would see it. Multi-line values are joined with `\n`
        /// and each line is trimmed.
        var value: String
        var isMultiline: Bool
        /// Inline comment stripped from a single-line value (including the `#`/`;`), if any.
        var inlineComment: String?
        /// The original raw lines (key line + continuation lines). Rewritten only when modified.
        var rawLines: [String]
    }

    enum Line: Equatable, Sendable {
        case blank(String)
        case comment(String)
        case section(name: String, raw: String)
        case entry(Entry)
        /// A line wakatime-cli cannot interpret. Kept verbatim and surfaced as an issue.
        case invalid(raw: String, reason: InvalidReason)
    }

    enum InvalidReason: Equatable, Sendable {
        /// `[name` without a closing bracket. wakatime-cli silently ignores this line.
        case unterminatedSection
        /// No `=` or `:`. go-ini refuses to load the whole file.
        case missingDelimiter
    }

    struct Issue: Equatable, Sendable, Identifiable {
        enum Severity: Sendable { case warning, error }
        var id: String { "\(lineNumber)-\(message)" }
        var lineNumber: Int
        var severity: Severity
        var message: String
    }

    private(set) var lines: [Line]
    private(set) var lineEnding: String
    private(set) var hasTrailingNewline: Bool

    static let defaultIndent = "    "

    // MARK: - Parsing

    init(text: String) {
        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        var raw = text.components(separatedBy: "\n").map { line -> String in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }
        var trailing = false
        if raw.last == "" {
            raw.removeLast()
            trailing = true
        }
        self.lineEnding = lineEnding
        self.hasTrailingNewline = trailing || raw.isEmpty
        self.lines = INIDocument.parse(raw)
    }

    init() {
        self.init(text: "")
    }

    private static func parse(_ raw: [String]) -> [Line] {
        var result: [Line] = []
        var i = 0
        while i < raw.count {
            let line = raw[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                result.append(.blank(line)); i += 1; continue
            }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                result.append(.comment(line)); i += 1; continue
            }
            if trimmed.hasPrefix("[") {
                if let close = trimmed.lastIndex(of: "]") {
                    let name = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
                        .trimmingCharacters(in: .whitespaces)
                    result.append(.section(name: name, raw: line))
                } else {
                    result.append(.invalid(raw: line, reason: .unterminatedSection))
                }
                i += 1; continue
            }

            guard let delimiter = trimmed.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
                result.append(.invalid(raw: line, reason: .missingDelimiter)); i += 1; continue
            }

            var key = String(trimmed[..<delimiter]).trimmingCharacters(in: .whitespaces)
            if key.count >= 2, let q = key.first, (q == "\"" || q == "`"), key.last == q {
                key = String(key.dropFirst().dropLast())
            }
            let rawValue = String(trimmed[trimmed.index(after: delimiter)...])
            let leftTrimmed = rawValue.drop(while: { $0 == " " || $0 == "\t" })

            if leftTrimmed.isEmpty {
                // Python-style multi-line value: following lines that begin with whitespace.
                var j = i + 1
                var items: [String] = []
                var rawLines = [line]
                while j < raw.count, let first = raw[j].first, first == " " || first == "\t" || first == "\u{0C}" {
                    rawLines.append(raw[j])
                    let item = raw[j].trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty { items.append(item) }
                    j += 1
                }
                let isMultiline = rawLines.count > 1
                result.append(.entry(Entry(key: key, value: items.joined(separator: "\n"),
                                           isMultiline: isMultiline, inlineComment: nil, rawLines: rawLines)))
                i = j
                continue
            }

            let (value, comment) = parseSingleLineValue(String(leftTrimmed))
            result.append(.entry(Entry(key: key, value: value, isMultiline: false,
                                       inlineComment: comment, rawLines: [line])))
            i += 1
        }
        return result
    }

    private static func parseSingleLineValue(_ value: String) -> (String, String?) {
        // Quoted values: """...""" or `...` are taken literally.
        for quote in ["\"\"\"", "`"] where value.hasPrefix(quote) && value.count > quote.count {
            let body = value.dropFirst(quote.count)
            if let end = body.range(of: quote, options: .backwards) {
                return (String(body[..<end.lowerBound]), nil)
            }
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let idx = trimmed.firstIndex(where: { $0 == "#" || $0 == ";" }) {
            let comment = String(trimmed[idx...])
            return (String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces), comment)
        }
        return (trimmed, nil)
    }

    // MARK: - Reading

    /// Names of all sections in file order (duplicates collapsed, case-insensitive).
    var sectionNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for case let .section(name, _) in lines where seen.insert(name.lowercased()).inserted {
            names.append(name)
        }
        return names
    }

    /// All entries in a section, in file order, with the section name they belong to.
    /// A `nil` section means the implicit default section (keys before any header).
    func entries(in section: String?) -> [Entry] {
        var current: String? = nil
        var out: [Entry] = []
        for line in lines {
            switch line {
            case .section(let name, _): current = name
            case .entry(let entry):
                if sectionMatches(current, section) { out.append(entry) }
            default: break
            }
        }
        return out
    }

    /// Effective entries of a section: later duplicates override earlier ones (go-ini behaviour),
    /// order follows first appearance.
    func effectiveEntries(in section: String) -> [Entry] {
        var order: [String] = []
        var map: [String: Entry] = [:]
        for entry in entries(in: section) {
            let k = entry.key.lowercased()
            if map[k] == nil { order.append(k) }
            map[k] = entry
        }
        return order.compactMap { map[$0] }
    }

    func entry(section: String, key: String) -> Entry? {
        entries(in: section).last { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }

    func value(section: String, key: String) -> String? {
        entry(section: section, key: key)?.value
    }

    func hasSection(_ section: String) -> Bool {
        lines.contains { if case .section(let n, _) = $0 { return n.caseInsensitiveCompare(section) == .orderedSame }; return false }
    }

    /// Problems that would change how wakatime-cli reads the file.
    var issues: [Issue] {
        var result: [Issue] = []
        var lineNumber = 1
        var current: String? = nil
        var seen: [String: Int] = [:]
        for line in lines {
            switch line {
            case .invalid(let raw, .missingDelimiter):
                result.append(Issue(lineNumber: lineNumber, severity: .error,
                                    message: "Line \(lineNumber) has no “=”. wakatime-cli cannot load a config with this line: “\(Redaction.redactSecrets(in: raw))”"))
            case .invalid(let raw, .unterminatedSection):
                result.append(Issue(lineNumber: lineNumber, severity: .warning,
                                    message: "Line \(lineNumber) looks like a section header without “]”. wakatime-cli ignores it: “\(raw.trimmingCharacters(in: .whitespaces))”"))
            case .section(let name, _):
                current = name
            case .entry(let entry):
                let id = "\((current ?? "").lowercased()).\(entry.key.lowercased())"
                if let first = seen[id] {
                    result.append(Issue(lineNumber: lineNumber, severity: .warning,
                                        message: "“\(entry.key)” is set more than once in [\(current ?? "default")] (lines \(first) and \(lineNumber)). The last one wins."))
                } else {
                    seen[id] = lineNumber
                }
            default: break
            }
            lineNumber += lineSpan(line)
        }
        return result
    }

    private func lineSpan(_ line: Line) -> Int {
        if case .entry(let e) = line { return max(1, e.rawLines.count) }
        return 1
    }

    // MARK: - Writing

    /// Sets (or removes, when `value` is nil) a key. Existing entries are rewritten in place,
    /// preserving the original key spelling. New keys are appended to the end of the section.
    mutating func set(_ value: String?, section: String, key: String) {
        guard let value else { remove(section: section, key: key); return }

        if let index = lastEntryIndex(section: section, key: key),
           case .entry(let existing) = lines[index] {
            if existing.value == value, existing.inlineComment == nil { return }
            lines[index] = .entry(INIDocument.makeEntry(key: existing.key, value: value))
            return
        }

        let newEntry = Line.entry(INIDocument.makeEntry(key: key, value: value))
        if let insertAt = insertionIndex(forSection: section) {
            lines.insert(newEntry, at: insertAt)
        } else {
            if let last = lines.last, !isBlank(last) { lines.append(.blank("")) }
            lines.append(.section(name: section, raw: "[\(section)]"))
            lines.append(newEntry)
        }
    }

    /// Removes every occurrence of the key in the section.
    mutating func remove(section: String, key: String) {
        var current: String? = nil
        lines = lines.filter { line in
            switch line {
            case .section(let name, _): current = name; return true
            case .entry(let e):
                return !(sectionMatches(current, section) && e.key.caseInsensitiveCompare(key) == .orderedSame)
            default: return true
            }
        }
    }

    /// Renders the full file. Untouched lines are emitted byte-for-byte.
    func serialized() -> String {
        var out: [String] = []
        for line in lines {
            switch line {
            case .blank(let raw), .comment(let raw): out.append(raw)
            case .section(_, let raw): out.append(raw)
            case .invalid(let raw, _): out.append(raw)
            case .entry(let e): out.append(contentsOf: e.rawLines)
            }
        }
        if out.isEmpty { return "" }
        return out.joined(separator: lineEnding) + (hasTrailingNewline ? lineEnding : "")
    }

    static func makeEntry(key: String, value: String) -> Entry {
        let items = value.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if value.contains("\n") {
            let raw = ["\(key) ="] + items.map { defaultIndent + $0 }
            return Entry(key: key, value: items.joined(separator: "\n"), isMultiline: true, inlineComment: nil, rawLines: raw)
        }
        return Entry(key: key, value: value, isMultiline: false, inlineComment: nil, rawLines: ["\(key) = \(value)"])
    }

    // MARK: - Helpers

    private func sectionMatches(_ current: String?, _ wanted: String?) -> Bool {
        switch (current, wanted) {
        case (nil, nil): return true
        case let (c?, w?): return c.caseInsensitiveCompare(w) == .orderedSame
        default: return false
        }
    }

    private func isBlank(_ line: Line) -> Bool {
        if case .blank = line { return true }
        return false
    }

    private func lastEntryIndex(section: String, key: String) -> Int? {
        var current: String? = nil
        var found: Int?
        for (i, line) in lines.enumerated() {
            switch line {
            case .section(let name, _): current = name
            case .entry(let e) where sectionMatches(current, section) && e.key.caseInsensitiveCompare(key) == .orderedSame:
                found = i
            default: break
            }
        }
        return found
    }

    /// Index just after the last non-blank line of the last block of `section`.
    private func insertionIndex(forSection section: String) -> Int? {
        var lastHeader: Int?
        for (i, line) in lines.enumerated() {
            if case .section(let name, _) = line, name.caseInsensitiveCompare(section) == .orderedSame { lastHeader = i }
        }
        guard let header = lastHeader else { return nil }
        var end = header + 1
        while end < lines.count {
            if case .section = lines[end] { break }
            end += 1
        }
        // Walk back over trailing blank lines so the new key sits with its siblings.
        var insert = end
        while insert > header + 1, isBlank(lines[insert - 1]) { insert -= 1 }
        return insert
    }
}
