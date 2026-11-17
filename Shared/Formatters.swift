import Foundation

nonisolated enum Formatters {

    /// 0 → "0m", 2700 → "45m", 7512 → "2h 5m".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Spoken/long form for accessibility and tooltips: "2 hours 5 minutes".
    static func longDuration(_ seconds: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .full
        f.zeroFormattingBehavior = .dropAll
        return seconds < 60 ? "no time" : (f.string(from: seconds) ?? duration(seconds))
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }

    static func percent(_ value: Double) -> String {
        value >= 10 || value == 0 ? "\(Int(value.rounded()))%" : String(format: "%.1f%%", value)
    }
}
