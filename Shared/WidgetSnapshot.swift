import Foundation

/// The data the desktop widgets display. Hackatime Studio writes it to the shared App Group
/// container after every dashboard refresh; the (sandboxed) widget extension only reads it.
/// The API key never leaves the app.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Goal: Codable, Equatable, Sendable {
        var targetSeconds: Double
        var trackedSeconds: Double

        var fraction: Double { targetSeconds > 0 ? min(1, trackedSeconds / targetSeconds) : 0 }
        var percent: Int { targetSeconds > 0 ? Int((trackedSeconds / targetSeconds * 100).rounded()) : 0 }
        var isComplete: Bool { trackedSeconds >= targetSeconds }
        var remainingSeconds: Double { max(0, targetSeconds - trackedSeconds) }
    }

    var fetchedAt: Date
    var timeZoneID: String
    /// The Hackatime-time-zone day (`yyyy-MM-dd`) that `todaySeconds` and `goal` belong to.
    var dayKey: String
    var todaySeconds: Double
    /// Nil when no daily goal is set on Hackatime.
    var goal: Goal?
    /// Coding seconds per day (`yyyy-MM-dd`). Missing days had no activity.
    var dailySeconds: [String: Double]

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    var calendar: Calendar {
        var c = Calendar.current
        c.timeZone = timeZone
        return c
    }

    func seconds(on date: Date) -> Double { dailySeconds[Self.dayKey(date, calendar: calendar)] ?? 0 }

    var intensity: ActivityIntensity { ActivityIntensity(values: dailySeconds.values) }

    /// Today's goal as of `now`. After midnight (before the app refreshes) tracked time is zero.
    func goal(at now: Date) -> Goal? {
        guard var goal else { return nil }
        if Self.dayKey(now, calendar: calendar) != dayKey { goal.trackedSeconds = 0 }
        return goal
    }

    /// Data older than this gets an "updated … ago" note in the widget.
    static let staleAfter: TimeInterval = 2 * 3600

    func isStale(at now: Date) -> Bool { now.timeIntervalSince(fetchedAt) > Self.staleAfter }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Same content, ignoring when it was fetched.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var a = self, b = other
        a.fetchedAt = .distantPast
        b.fetchedAt = .distantPast
        return a == b
    }

    // MARK: - Persistence (App Group container)

    /// Team-prefixed so it works for the unsandboxed app and the sandboxed extension without a
    /// provisioning profile.
    static let appGroupID = "FU24QF42S6.xyz.elipseday.hackatime-studio"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: "widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.fileURL else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func remove() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Sample (widget gallery placeholder)

    static func sample(now: Date = Date()) -> WidgetSnapshot {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var daily: [String: Double] = [:]
        // Deterministic pseudo-random pattern so the gallery preview looks like real activity.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for offset in 0..<182 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let roll = Double(seed >> 33) / Double(1 << 31)
            guard roll > 0.45, let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            daily[dayKey(day, calendar: calendar)] = (roll - 0.45) * 5 * 3600
        }
        let todayKey = dayKey(now, calendar: calendar)
        daily[todayKey] = 39 * 60
        return WidgetSnapshot(fetchedAt: now, timeZoneID: calendar.timeZone.identifier, dayKey: todayKey,
                              todaySeconds: 39 * 60, goal: Goal(targetSeconds: 3600, trackedSeconds: 39 * 60),
                              dailySeconds: daily)
    }
}
