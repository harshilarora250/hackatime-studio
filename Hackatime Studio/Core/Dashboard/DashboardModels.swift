import Foundation

nonisolated enum StatsRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        case .year: "12 months"
        }
    }

    func interval(now: Date, calendar: Calendar) -> (Date, Date) {
        let startOfToday = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: startOfToday)!.addingTimeInterval(-1)
        let days: Int
        switch self {
        case .today: days = 0
        case .week: days = 6
        case .month: days = 29
        case .year: days = 364
        }
        return (calendar.date(byAdding: .day, value: -days, to: startOfToday)!, end)
    }
}

nonisolated enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, week, month, streak, activity, languages, projects, goal, tracking, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        case .month: "This month"
        case .streak: "Streak"
        case .activity: "Coding activity"
        case .languages: "Languages"
        case .projects: "Projects"
        case .goal: "Daily goal"
        case .tracking: "Tracking status"
        case .recent: "Recent activity"
        }
    }

    var summary: String {
        switch self {
        case .today: "Time coded today, in your Hackatime time zone."
        case .week: "Total for the current calendar week, compared with last week."
        case .month: "Total for the current calendar month."
        case .streak: "Consecutive days with coding activity, as calculated by Hackatime."
        case .activity: "A contribution-style graph of daily coding time."
        case .languages: "Time per language for a chosen range."
        case .projects: "Time per project for a chosen range."
        case .goal: "Progress toward your daily goal. Only daily goals are available through the API."
        case .tracking: "When Hackatime last received a heartbeat, and from which editor."
        case .recent: "Today’s coding sessions and the last few active days."
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .week: "calendar"
        case .month: "calendar.badge.clock"
        case .streak: "flame"
        case .activity: "square.grid.3x3.fill"
        case .languages: "chevron.left.forwardslash.chevron.right"
        case .projects: "folder"
        case .goal: "target"
        case .tracking: "dot.radiowaves.left.and.right"
        case .recent: "clock.arrow.circlepath"
        }
    }

    enum Span: Int, Codable, Sendable { case small = 1, medium = 2, wide = 4 }

    var span: Span {
        switch self {
        case .today, .week, .month, .streak, .goal, .tracking: .small
        case .languages, .projects, .recent: .medium
        case .activity: .wide
        }
    }

    var supportsRange: Bool { self == .languages || self == .projects }
    var supportsLimit: Bool { self == .languages || self == .projects }
    var supportsWeeks: Bool { self == .activity }
}

nonisolated struct WidgetConfig: Codable, Hashable, Identifiable, Sendable {
    var kind: WidgetKind
    var isVisible: Bool = true
    var range: StatsRange = .week
    var limit: Int = 6
    var weeks: Int = 26
    var id: WidgetKind { kind }
}

nonisolated struct DashboardLayout: Codable, Equatable, Sendable {
    var widgets: [WidgetConfig]

    static let `default` = DashboardLayout(widgets: [
        WidgetConfig(kind: .today),
        WidgetConfig(kind: .week),
        WidgetConfig(kind: .month),
        WidgetConfig(kind: .streak),
        WidgetConfig(kind: .activity, weeks: 26),
        WidgetConfig(kind: .languages, range: .week, limit: 6),
        WidgetConfig(kind: .projects, range: .week, limit: 6),
        WidgetConfig(kind: .goal),
        WidgetConfig(kind: .tracking),
        WidgetConfig(kind: .recent),
    ])

    var visible: [WidgetConfig] { widgets.filter(\.isVisible) }

    func config(_ kind: WidgetKind) -> WidgetConfig? { widgets.first { $0.kind == kind } }

    /// Adds any widget kinds introduced after the layout was saved (hidden, at the end).
    func normalized() -> DashboardLayout {
        var copy = self
        var seen = Set<WidgetKind>()
        copy.widgets = copy.widgets.filter { seen.insert($0.kind).inserted }
        for kind in WidgetKind.allCases where !seen.contains(kind) {
            copy.widgets.append(WidgetConfig(kind: kind, isVisible: false))
        }
        return copy
    }

    private static let key = "studio.dashboard.layout.v1"

    static func load(_ defaults: UserDefaults = .standard) -> DashboardLayout {
        guard let data = defaults.data(forKey: key),
              let layout = try? JSONDecoder().decode(DashboardLayout.self, from: data) else { return .default }
        return layout.normalized()
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// Everything the dashboard shows, fetched from the real API.
nonisolated struct DashboardSnapshot: Equatable, Sendable {
    var fetchedAt: Date
    var timeZone: TimeZone
    var today: StatusBarToday?
    var days: [DailySummary]
    var stats: [StatsRange: UserStats]
    var spansToday: [ActivitySpan]?
    var latest: MostRecentHeartbeatResponse?
    /// Per-part failures, so one failing endpoint doesn't blank the whole dashboard.
    var failures: [String: String]

    var calendar: Calendar {
        var c = Calendar.current
        c.timeZone = timeZone
        return c
    }

    func seconds(on date: Date) -> Double {
        let key = Self.dayKey(date, calendar: calendar)
        return days.first { $0.id == key }?.seconds ?? 0
    }

    func total(from start: Date, through end: Date) -> Double {
        let s = Self.dayKey(start, calendar: calendar), e = Self.dayKey(end, calendar: calendar)
        return days.filter { $0.id >= s && $0.id <= e }.reduce(0) { $0 + $1.seconds }
    }

    var weekTotal: Double {
        let now = Date()
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return total(from: start, through: now)
    }

    var previousWeekTotal: Double? {
        let now = Date()
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let lastStart = calendar.date(byAdding: .day, value: -7, to: thisWeek.start) else { return nil }
        // Same elapsed portion of last week, for a fair comparison.
        let elapsed = now.timeIntervalSince(thisWeek.start)
        return total(from: lastStart, through: lastStart.addingTimeInterval(elapsed))
    }

    var monthTotal: Double {
        let now = Date()
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return total(from: start, through: now)
    }

    var activeDaysThisMonth: Int {
        let now = Date()
        let start = Self.dayKey(calendar.dateInterval(of: .month, for: now)?.start ?? now, calendar: calendar)
        return days.filter { $0.id >= start && $0.seconds > 0 }.count
    }

    var streak: Int? { stats.values.compactMap(\.streak).first }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
