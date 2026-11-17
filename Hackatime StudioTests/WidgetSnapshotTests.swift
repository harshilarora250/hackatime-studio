import Foundation
import Testing
@testable import Hackatime_Studio

@Suite("Desktop widget snapshot")
struct WidgetSnapshotTests {

    let tz = TimeZone(identifier: "America/New_York")!

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func dashboard(today: String, days: String) throws -> DashboardSnapshot {
        let t = try JSONDecoder().decode(DataEnvelope<StatusBarToday>.self, from: Data(today.utf8)).data
        let d = try JSONDecoder().decode(SummariesResponse.self, from: Data(days.utf8)).data
        return DashboardSnapshot(fetchedAt: date("2026-11-17T15:00:00Z"), timeZone: tz, today: t, days: d,
                                 stats: [:], spansToday: nil, latest: nil, failures: [:])
    }

    @Test func buildsFromDashboard() throws {
        let snap = try dashboard(
            today: #"{"data":{"grand_total":{"total_seconds":2340},"goal":{"target_seconds":3600,"tracked_seconds":2340}}}"#,
            days: #"{"data":[{"grand_total":{"total_seconds":1800},"range":{"date":"2026-11-16"}},{"grand_total":{"total_seconds":1200},"range":{"date":"2026-11-17"}},{"grand_total":{"total_seconds":0},"range":{"date":"2026-11-15"}}]}"#)
        let widget = try #require(WidgetBridge.makeWidgetSnapshot(from: snap))
        #expect(widget.dayKey == "2026-11-17")
        // The fresher status-bar total wins over today's summary row.
        #expect(widget.dailySeconds["2026-11-17"] == 2340)
        #expect(widget.dailySeconds["2026-11-16"] == 1800)
        #expect(widget.dailySeconds["2026-11-15"] == nil)
        let goal = try #require(widget.goal)
        #expect(goal.percent == 65)
        #expect(goal.remainingSeconds == 1260)
        #expect(!goal.isComplete)
    }

    @Test func noGoalWhenTargetIsZero() throws {
        let snap = try dashboard(today: #"{"data":{"grand_total":{"total_seconds":60}}}"#, days: #"{"data":[]}"#)
        #expect(WidgetBridge.makeWidgetSnapshot(from: snap)?.goal == nil)
    }

    @Test func skipsEmptyRefresh() {
        let empty = DashboardSnapshot(fetchedAt: Date(), timeZone: tz, today: nil, days: [], stats: [:],
                                      spansToday: nil, latest: nil, failures: ["today": "offline"])
        #expect(WidgetBridge.makeWidgetSnapshot(from: empty) == nil)
    }

    @Test func goalResetsAfterMidnight() {
        let snapshot = WidgetSnapshot(fetchedAt: date("2026-11-17T15:00:00Z"), timeZoneID: tz.identifier, dayKey: "2026-11-17",
                                      todaySeconds: 2340, goal: .init(targetSeconds: 3600, trackedSeconds: 2340), dailySeconds: [:])
        #expect(snapshot.goal(at: date("2026-11-18T04:30:00Z"))?.trackedSeconds == 2340) // 23:30 New York
        #expect(snapshot.goal(at: date("2026-11-18T05:30:00Z"))?.trackedSeconds == 0)    // 00:30 next day
        #expect(snapshot.isStale(at: date("2026-11-17T18:00:00Z")))
        #expect(!snapshot.isStale(at: date("2026-11-17T16:00:00Z")))
    }

    @Test func intensityQuartiles() {
        let intensity = ActivityIntensity(values: [0, 100, 200, 300, 400, 500])
        #expect(intensity.level(0) == 0)
        #expect(intensity.level(100) == 1)
        #expect(intensity.level(500) == 4)
        #expect(ActivityIntensity(values: []).level(10) == 4)
    }

    @Test func columnsEndWithCurrentWeek() {
        let now = date("2026-11-17T15:00:00Z")
        let cols = ActivityIntensity.columns(weeks: 16, now: now, calendar: calendar)
        #expect(cols.count == 16)
        #expect(cols.allSatisfy { $0.count == 7 })
        #expect(cols.last!.contains { calendar.isDate($0, inSameDayAs: now) })
    }

    @Test func roundTripsThroughJSON() throws {
        let sample = WidgetSnapshot.sample()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let back = try decoder.decode(WidgetSnapshot.self, from: encoder.encode(sample))
        #expect(back.hasSameContent(as: sample))
    }
}
