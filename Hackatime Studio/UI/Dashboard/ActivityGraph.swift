import SwiftUI

/// GitHub-style contribution graph built from Hackatime daily summaries.
/// Intensity is quantised by quartiles of the user's own non-zero days.
struct ActivityGraph: View {
    var snapshot: DashboardSnapshot
    var weeks: Int

    @State private var hovered: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var width: CGFloat = 700

    private var calendar: Calendar { snapshot.calendar }

    private var columns: [[Date]] {
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: weekStart)!
        return (0..<weeks).map { w in
            (0..<7).map { d in calendar.date(byAdding: .day, value: w * 7 + d, to: first)! }
        }
    }

    private var thresholds: [Double] {
        let values = snapshot.days.map(\.seconds).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return [1, 2, 3] }
        func q(_ p: Double) -> Double { values[min(values.count - 1, Int(Double(values.count - 1) * p))] }
        return [q(0.25), q(0.5), q(0.75)]
    }

    private func level(_ seconds: Double) -> Int {
        guard seconds > 0 else { return 0 }
        let t = thresholds
        if seconds <= t[0] { return 1 }
        if seconds <= t[1] { return 2 }
        if seconds <= t[2] { return 3 }
        return 4
    }

    var body: some View {
        let cols = columns
        let today = calendar.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 10) {
            let labelWidth: CGFloat = 28
            let gap: CGFloat = 3
            let cell = max(7, min(22, (width - labelWidth - gap * CGFloat(weeks - 1)) / CGFloat(weeks)))
            VStack(alignment: .leading, spacing: 4) {
                monthLabels(cols, cell: cell, gap: gap, labelWidth: labelWidth)
                HStack(alignment: .top, spacing: gap) {
                    weekdayLabels(cell: cell, gap: gap).frame(width: labelWidth - gap, alignment: .leading)
                    ForEach(Array(cols.enumerated()), id: \.offset) { index, days in
                        VStack(spacing: gap) {
                            ForEach(days, id: \.self) { day in
                                cellView(day, today: today, size: cell)
                            }
                        }
                        .opacity(revealed || reduceMotion ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(Double(index) * 0.35 / Double(max(weeks, 1))), value: revealed)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }

            HStack(spacing: 6) {
                Text(hoverText)
                    .font(.studioCallout.monospacedDigit())
                    .foregroundStyle(hovered == nil ? Theme.inkTertiary : Theme.ink)
                    .contentTransition(.opacity)
                Spacer()
                Text("Less").font(.studioCaption).foregroundStyle(Theme.inkTertiary)
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: Theme.Radius.cell, style: .continuous).fill(Theme.ramp[i]).frame(width: 10, height: 10)
                }
                Text("More").font(.studioCaption).foregroundStyle(Theme.inkTertiary)
            }
            .accessibilityHidden(true)
        }
        .onAppear { revealed = true }
    }

    private var hoverText: String {
        guard let hovered else {
            let total = snapshot.days.reduce(0) { $0 + $1.seconds }
            let active = snapshot.days.filter { $0.seconds > 0 }.count
            return "\(Formatters.duration(total)) across \(active) active days"
        }
        let f = DateFormatter()
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE d MMM yyyy"
        let s = snapshot.seconds(on: hovered)
        return "\(f.string(from: hovered)) — \(s > 0 ? Formatters.duration(s) : "no coding")"
    }

    @ViewBuilder
    private func cellView(_ day: Date, today: Date, size: CGFloat) -> some View {
        let future = day > today
        let seconds = snapshot.seconds(on: day)
        let isHovered = hovered == day
        RoundedRectangle(cornerRadius: Theme.Radius.cell, style: .continuous)
            .fill(future ? Color.clear : Theme.ramp[level(seconds)])
            .overlay {
                if day == today {
                    RoundedRectangle(cornerRadius: Theme.Radius.cell, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(isHovered ? 1.25 : 1)
            .animation(Theme.Motion.hover, value: isHovered)
            .onHover { inside in
                if inside, !future { hovered = day } else if hovered == day { hovered = nil }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel(day, seconds: seconds, future: future))
            .accessibilityHidden(future)
    }

    private func accessibilityLabel(_ day: Date, seconds: Double, future: Bool) -> String {
        let f = DateFormatter()
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEE d MMMM"
        return "\(f.string(from: day)): \(Formatters.longDuration(seconds))"
    }

    private func monthLabels(_ cols: [[Date]], cell: CGFloat, gap: CGFloat, labelWidth: CGFloat) -> some View {
        let f = DateFormatter()
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM"
        return ZStack(alignment: .topLeading) {
            ForEach(Array(cols.enumerated()), id: \.offset) { index, days in
                if let first = days.first, index == 0 || calendar.component(.month, from: first) != calendar.component(.month, from: cols[index - 1].first!) {
                    if index < cols.count - 1 || cols.count < 3 {
                        Text(f.string(from: days.first { calendar.component(.day, from: $0) <= 7 } ?? first))
                            .font(.studioCaption)
                            .foregroundStyle(Theme.inkTertiary)
                            .offset(x: labelWidth + CGFloat(index) * (cell + gap))
                    }
                }
            }
        }
        .frame(height: 12, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func weekdayLabels(cell: CGFloat, gap: CGFloat) -> some View {
        let symbols = calendar.veryShortWeekdaySymbols
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                let weekday = (calendar.firstWeekday - 1 + row) % 7
                Text(row % 2 == 1 ? symbols[weekday] : " ")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(height: cell)
            }
        }
        .accessibilityHidden(true)
    }
}
