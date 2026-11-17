import SwiftUI
import WidgetKit

nonisolated struct StudioEntry: TimelineEntry {
    let date: Date
    /// Nil until Hackatime Studio has refreshed at least once.
    let snapshot: WidgetSnapshot?
}

/// Reads the snapshot Hackatime Studio writes to the App Group. The app reloads the timelines
/// after each refresh; the timeline itself only needs to redraw at midnight (new day: the goal
/// resets and the graph moves on) and when the data becomes stale.
nonisolated struct StudioProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudioEntry {
        StudioEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (StudioEntry) -> Void) {
        let stored = WidgetSnapshot.load()
        completion(StudioEntry(date: Date(), snapshot: stored ?? (context.isPreview ? .sample() : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StudioEntry>) -> Void) {
        let now = Date()
        guard let snapshot = WidgetSnapshot.load() else {
            completion(Timeline(entries: [StudioEntry(date: now, snapshot: nil)], policy: .never))
            return
        }
        let calendar = snapshot.calendar
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        var dates: Set<Date> = [now, midnight]
        let staleAt = snapshot.fetchedAt.addingTimeInterval(WidgetSnapshot.staleAfter + 1)
        if staleAt > now, staleAt < midnight { dates.insert(staleAt) }
        let entries = dates.sorted().map { StudioEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }
}
