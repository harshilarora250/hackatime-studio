import Foundation

/// Decodes numbers that the API sometimes sends as integers, floats or numeric strings.
nonisolated struct FlexibleNumber: Decodable, Hashable, Sendable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self), let d = Double(s) { value = d }
        else { value = 0 }
    }
}

// MARK: - /api/hackatime/v1/users/current

nonisolated struct UserProfile: Decodable, Hashable, Sendable {
    var id: String?
    var username: String?
    var displayName: String?
    var photo: String?
    var timezone: String?

    enum CodingKeys: String, CodingKey {
        case id, username, photo, timezone
        case displayName = "display_name"
    }

    var bestName: String { displayName ?? username ?? "Hackatime user" }
    var timeZone: TimeZone { timezone.flatMap(TimeZone.init(identifier:)) ?? .current }
}

nonisolated struct DataEnvelope<T: Decodable & Sendable>: Decodable, Sendable { var data: T }

// MARK: - /users/current/statusbar/today

nonisolated struct StatusBarToday: Decodable, Hashable, Sendable {
    struct GrandTotal: Decodable, Hashable, Sendable {
        var text: String?
        var totalSeconds: FlexibleNumber?
        enum CodingKeys: String, CodingKey { case text; case totalSeconds = "total_seconds" }
    }
    struct Goal: Decodable, Hashable, Sendable {
        var targetSeconds: FlexibleNumber?
        var trackedSeconds: FlexibleNumber?
        var completionPercent: FlexibleNumber?
        var complete: Bool?
        enum CodingKeys: String, CodingKey {
            case complete
            case targetSeconds = "target_seconds"
            case trackedSeconds = "tracked_seconds"
            case completionPercent = "completion_percent"
        }
    }
    var grandTotal: GrandTotal?
    var goal: Goal?
    enum CodingKeys: String, CodingKey { case goal; case grandTotal = "grand_total" }

    var todaySeconds: Double { grandTotal?.totalSeconds?.value ?? 0 }
}

// MARK: - /users/current/summaries

nonisolated struct NamedDuration: Decodable, Hashable, Sendable, Identifiable {
    var name: String
    var totalSeconds: Double
    var percent: Double?
    var color: String?
    var id: String { name }

    enum CodingKeys: String, CodingKey { case name, percent, color; case totalSeconds = "total_seconds" }

    init(name: String, totalSeconds: Double, percent: Double? = nil, color: String? = nil) {
        self.name = name; self.totalSeconds = totalSeconds; self.percent = percent; self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
        totalSeconds = (try? c.decode(FlexibleNumber.self, forKey: .totalSeconds))?.value ?? 0
        percent = (try? c.decode(FlexibleNumber.self, forKey: .percent))?.value
        color = try? c.decode(String.self, forKey: .color)
    }
}

nonisolated struct DailySummary: Decodable, Hashable, Sendable, Identifiable {
    struct Range: Decodable, Hashable, Sendable { var date: String }
    struct GrandTotal: Decodable, Hashable, Sendable {
        var totalSeconds: FlexibleNumber?
        enum CodingKeys: String, CodingKey { case totalSeconds = "total_seconds" }
    }
    var range: Range
    var grandTotal: GrandTotal?
    var projects: [NamedDuration]?
    var id: String { range.date }
    var seconds: Double { grandTotal?.totalSeconds?.value ?? 0 }

    enum CodingKeys: String, CodingKey { case range, projects; case grandTotal = "grand_total" }
}

nonisolated struct SummariesResponse: Decodable, Hashable, Sendable {
    var data: [DailySummary]
}

// MARK: - /api/v1/users/my/stats

nonisolated struct UserStats: Decodable, Hashable, Sendable {
    var totalSeconds: Double
    var languages: [NamedDuration]
    var projects: [NamedDuration]
    var streak: Int?

    enum CodingKeys: String, CodingKey { case languages, projects, streak; case totalSeconds = "total_seconds" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalSeconds = (try? c.decode(FlexibleNumber.self, forKey: .totalSeconds))?.value ?? 0
        languages = (try? c.decode([NamedDuration].self, forKey: .languages)) ?? []
        projects = (try? c.decode([NamedDuration].self, forKey: .projects)) ?? []
        streak = (try? c.decode(FlexibleNumber.self, forKey: .streak)).map { Int($0.value) }
    }
}

// MARK: - /api/v1/users/my/heartbeats/spans

nonisolated struct ActivitySpan: Decodable, Hashable, Sendable, Identifiable {
    var start: Date
    var end: Date
    var duration: Double
    var id: Date { start }

    enum CodingKeys: String, CodingKey { case duration; case start = "start_time"; case end = "end_time" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = Date(timeIntervalSince1970: try c.decode(FlexibleNumber.self, forKey: .start).value)
        end = Date(timeIntervalSince1970: try c.decode(FlexibleNumber.self, forKey: .end).value)
        duration = (try? c.decode(FlexibleNumber.self, forKey: .duration))?.value ?? end.timeIntervalSince(start)
    }
}

nonisolated struct SpansResponse: Decodable, Sendable { var spans: [ActivitySpan] }

// MARK: - /api/v1/my/heartbeats/most_recent

nonisolated struct RecentHeartbeat: Decodable, Hashable, Sendable {
    var time: Date?
    var project: String?
    var language: String?
    var editor: String?
    var operatingSystem: String?
    var machine: String?
    var category: String?

    enum CodingKeys: String, CodingKey {
        case time, project, language, editor, machine, category
        case operatingSystem = "operating_system"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = (try? c.decode(FlexibleNumber.self, forKey: .time)).map { Date(timeIntervalSince1970: $0.value) }
        project = try? c.decode(String.self, forKey: .project)
        language = try? c.decode(String.self, forKey: .language)
        editor = try? c.decode(String.self, forKey: .editor)
        operatingSystem = try? c.decode(String.self, forKey: .operatingSystem)
        machine = try? c.decode(String.self, forKey: .machine)
        category = try? c.decode(String.self, forKey: .category)
    }
}

nonisolated struct MostRecentHeartbeatResponse: Decodable, Hashable, Sendable {
    var hasHeartbeat: Bool
    var heartbeat: RecentHeartbeat?
    var editor: String?
    enum CodingKeys: String, CodingKey { case heartbeat, editor; case hasHeartbeat = "has_heartbeat" }
}
