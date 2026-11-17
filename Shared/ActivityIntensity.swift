import Foundation

/// Maps a day's coding time to one of five ramp levels (0 = none), quantised by the quartiles of
/// the user's own non-zero days. Shared so the dashboard graph and the desktop widget agree.
nonisolated struct ActivityIntensity: Equatable, Sendable {
    let thresholds: [Double]

    init<S: Sequence>(values: S) where S.Element == Double {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { thresholds = [1, 2, 3]; return }
        func q(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
        thresholds = [q(0.25), q(0.5), q(0.75)]
    }

    func level(_ seconds: Double) -> Int {
        guard seconds > 0 else { return 0 }
        if seconds <= thresholds[0] { return 1 }
        if seconds <= thresholds[1] { return 2 }
        if seconds <= thresholds[2] { return 3 }
        return 4
    }

    /// `weeks` columns of 7 days each, ending with the week containing `now`. Columns start on the
    /// calendar's first weekday, so the last column can contain future days.
    static func columns(weeks: Int, now: Date, calendar: Calendar) -> [[Date]] {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: weekStart)!
        return (0..<weeks).map { w in
            (0..<7).map { d in calendar.date(byAdding: .day, value: w * 7 + d, to: first)! }
        }
    }
}
