import Foundation

/// Central place for keeping API keys out of the UI, logs and error messages.
nonisolated enum Redaction {

    /// `waka_1234…cdef` → `waka_••••••••cdef`. Short or empty strings are fully masked.
    static func mask(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > 8 else { return String(repeating: "•", count: max(trimmed.count, 4)) }
        var prefix = ""
        if let underscore = trimmed.firstIndex(of: "_"), trimmed.distance(from: trimmed.startIndex, to: underscore) <= 6 {
            prefix = String(trimmed[...underscore])
        }
        return prefix + String(repeating: "•", count: 8) + trimmed.suffix(4)
    }

    /// Patterns that look like credentials: UUID-style keys, `waka_` keys, `api_key=...` pairs,
    /// and `|key` suffixes in `[api_urls]` values.
    private static let patterns: [NSRegularExpression] = [
        #"(?i)(api_?key\s*[=:]\s*)([^\s&#;]+)"#,
        #"(?i)waka_[0-9a-f-]{8,}"#,
        #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
        #"(?i)(Bearer\s+)([^\s]+)"#,
        #"(https?://[^\s|]+\|)([^\s]+)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Removes anything that looks like an API key from free text (logs, error output, raw lines).
    static func redactSecrets(in text: String, knownSecrets: [String] = []) -> String {
        var result = text
        for secret in knownSecrets where secret.count >= 6 {
            result = result.replacingOccurrences(of: secret, with: "••••••••")
        }
        for regex in patterns {
            let range = NSRange(result.startIndex..., in: result)
            if regex.numberOfCaptureGroups >= 2 {
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1••••••••")
            } else {
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "••••••••")
            }
        }
        return result
    }
}
