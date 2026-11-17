import Foundation
import WidgetKit

/// Hands dashboard data to the desktop widgets through the shared App Group container.
/// The widgets never talk to Hackatime themselves, so they update whenever Studio refreshes.
enum WidgetBridge {

    static func publish(_ snapshot: DashboardSnapshot) {
        guard let widget = makeWidgetSnapshot(from: snapshot) else { return }
        let previous = WidgetSnapshot.load()
        do { try widget.save() } catch { return }
        // Skip reloads that wouldn't change what's drawn, unless the widget is showing a stale note.
        if let previous, previous.hasSameContent(as: widget), !previous.isStale(at: widget.fetchedAt) { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func makeWidgetSnapshot(from snapshot: DashboardSnapshot) -> WidgetSnapshot? {
        // Nothing useful came back (e.g. offline on first launch): keep whatever the widget has.
        guard snapshot.today != nil || !snapshot.days.isEmpty else { return nil }
        let calendar = snapshot.calendar
        let todayKey = WidgetSnapshot.dayKey(snapshot.fetchedAt, calendar: calendar)

        var daily: [String: Double] = [:]
        for day in snapshot.days where day.seconds > 0 { daily[day.id] = max(daily[day.id] ?? 0, day.seconds) }
        // The status bar total is fresher than today's summary row.
        let todaySeconds = max(snapshot.today?.todaySeconds ?? 0, daily[todayKey] ?? 0)
        if todaySeconds > 0 { daily[todayKey] = todaySeconds }

        var goal: WidgetSnapshot.Goal?
        if let g = snapshot.today?.goal, let target = g.targetSeconds?.value, target > 0 {
            goal = .init(targetSeconds: target, trackedSeconds: g.trackedSeconds?.value ?? todaySeconds)
        }

        return WidgetSnapshot(fetchedAt: snapshot.fetchedAt, timeZoneID: snapshot.timeZone.identifier,
                              dayKey: todayKey, todaySeconds: todaySeconds, goal: goal, dailySeconds: daily)
    }
}
