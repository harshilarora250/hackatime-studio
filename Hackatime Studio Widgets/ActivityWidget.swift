import SwiftUI
import WidgetKit

struct ActivityWidget: Widget {
    let kind = "xyz.elipseday.hackatime-studio.activity"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StudioProvider()) { entry in
            ActivityWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Coding Activity")
        .description("Your daily coding time from Hackatime as a contribution graph.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ActivityWidgetView: View {
    var entry: StudioEntry
    @Environment(\.widgetFamily) private var family

    private var isSmall: Bool { family == .systemSmall }
    private var weeks: Int { isSmall ? 8 : 16 }

    var body: some View {
        if let snapshot = entry.snapshot {
            let summary = ActivitySummary(snapshot: snapshot, weeks: weeks, now: entry.date)
            VStack(alignment: .leading, spacing: isSmall ? 8 : 7) {
                WidgetHeader(symbol: "square.grid.3x3.fill",
                             title: isSmall ? "Activity" : "Coding activity",
                             detail: isSmall ? nil : "last \(weeks) weeks")
                ActivityHeatmap(snapshot: snapshot, columns: summary.columns, now: entry.date, showLabels: !isSmall)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Coding activity, last \(weeks) weeks")
                    .accessibilityValue("\(Formatters.longDuration(summary.total)) across \(summary.activeDays) active days")
                footer(summary, snapshot: snapshot)
            }
        } else {
            VStack(alignment: .leading) {
                WidgetHeader(symbol: "square.grid.3x3.fill", title: isSmall ? "Activity" : "Coding activity")
                OpenStudioNote()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func footer(_ summary: ActivitySummary, snapshot: WidgetSnapshot) -> some View {
        Styled { style in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isSmall {
                    Text(Formatters.duration(summary.total))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(style.ink)
                    Spacer(minLength: 4)
                    if snapshot.isStale(at: entry.date) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(style.inkTertiary)
                    } else {
                        Text("\(summary.activeDays) days")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(style.inkTertiary)
                    }
                } else {
                    Text("\(Formatters.duration(summary.total)) across \(summary.activeDays) active days")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(style.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if snapshot.isStale(at: entry.date) {
                        StaleNote(fetchedAt: snapshot.fetchedAt, now: entry.date)
                    } else {
                        legend(style)
                    }
                }
            }
        }
    }

    private func legend(_ style: WidgetStyle) -> some View {
        HStack(spacing: 3) {
            Text("Less").font(.system(size: 9.5, weight: .medium)).foregroundStyle(style.inkTertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(style.ramp(level))
                    .frame(width: 8, height: 8)
            }
            Text("More").font(.system(size: 9.5, weight: .medium)).foregroundStyle(style.inkTertiary)
        }
        .accessibilityHidden(true)
    }
}

/// Totals for the days the widget shows.
struct ActivitySummary {
    let columns: [[Date]]
    let total: Double
    let activeDays: Int

    init(snapshot: WidgetSnapshot, weeks: Int, now: Date) {
        let calendar = snapshot.calendar
        columns = ActivityIntensity.columns(weeks: weeks, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let seconds = columns.joined().filter { $0 <= today }.map(snapshot.seconds(on:))
        total = seconds.reduce(0, +)
        activeDays = seconds.filter { $0 > 0 }.count
    }
}

/// The contribution grid, sized to fit the space it's given with square cells.
struct ActivityHeatmap: View {
    var snapshot: WidgetSnapshot
    var columns: [[Date]]
    var now: Date
    var showLabels: Bool

    private let gap: CGFloat = 3
    private var labelWidth: CGFloat { showLabels ? 14 : 0 }
    private var monthHeight: CGFloat { showLabels ? 13 : 0 }

    var body: some View {
        GeometryReader { geo in
            let weeks = CGFloat(columns.count)
            let byWidth = (geo.size.width - labelWidth - gap * (weeks - 1)) / weeks
            let byHeight = (geo.size.height - monthHeight - gap * 6) / 7
            let cell = max(4, floor(min(byWidth, byHeight)))
            grid(cell: cell)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    private func grid(cell: CGFloat) -> some View {
        let calendar = snapshot.calendar
        let today = calendar.startOfDay(for: now)
        let intensity = snapshot.intensity
        return Styled { style in
            VStack(alignment: .leading, spacing: 0) {
                if showLabels { monthLabels(cell: cell, style: style).frame(height: monthHeight, alignment: .topLeading) }
                HStack(alignment: .top, spacing: gap) {
                    if showLabels { weekdayLabels(cell: cell, style: style).frame(width: labelWidth - gap, alignment: .leading) }
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, days in
                        VStack(spacing: gap) {
                            ForEach(days, id: \.self) { day in
                                cellView(day, today: today, cell: cell, intensity: intensity, style: style)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: Date, today: Date, cell: CGFloat, intensity: ActivityIntensity, style: WidgetStyle) -> some View {
        let radius = max(2, cell * 0.22)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if day > today {
            Color.clear.frame(width: cell, height: cell)
        } else {
            let level = intensity.level(snapshot.seconds(on: day))
            shape
                .fill(style.ramp(level))
                .overlay {
                    if day == today { shape.strokeBorder(style.accent, lineWidth: 1) }
                }
                .frame(width: cell, height: cell)
                .widgetAccentable(level > 0)
        }
    }

    private func monthLabels(cell: CGFloat, style: WidgetStyle) -> some View {
        let calendar = snapshot.calendar
        let f = DateFormatter()
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM"
        return ZStack(alignment: .topLeading) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, days in
                // Label the column in which a month begins (not the last one: no room to its right).
                if index < columns.count - 1, let firstOfMonth = days.first(where: { calendar.component(.day, from: $0) == 1 }) {
                    Text(f.string(from: firstOfMonth))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(style.inkTertiary)
                        .fixedSize()
                        .offset(x: labelWidth + CGFloat(index) * (cell + gap))
                }
            }
        }
    }

    private func weekdayLabels(cell: CGFloat, style: WidgetStyle) -> some View {
        let calendar = snapshot.calendar
        let symbols = calendar.veryShortWeekdaySymbols
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 1 ? symbols[(calendar.firstWeekday - 1 + row) % 7] : " ")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(style.inkTertiary)
                    .frame(height: cell)
            }
        }
    }
}

#Preview("Small", as: .systemSmall) {
    ActivityWidget()
} timeline: {
    StudioEntry(date: .now, snapshot: .sample())
}

#Preview("Medium", as: .systemMedium) {
    ActivityWidget()
} timeline: {
    StudioEntry(date: .now, snapshot: .sample())
    StudioEntry(date: .now, snapshot: nil)
}
