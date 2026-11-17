import SwiftUI

/// Shared chrome for every dashboard widget.
struct WidgetCard<Content: View, Accessory: View>: View {
    var kind: WidgetKind
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkTertiary)
                    Eyebrow(kind.title)
                    if let subtitle { Text(subtitle).font(.studioCaption).foregroundStyle(Theme.inkTertiary) }
                    Spacer(minLength: 0)
                    accessory
                }
                content
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }
}

extension WidgetCard where Accessory == EmptyView {
    init(kind: WidgetKind, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(kind: kind, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

struct MetricText: View {
    var seconds: Double
    var font: Font = .studioMetric
    var body: some View {
        Text(Formatters.duration(seconds))
            .font(font)
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
            .accessibilityLabel(Formatters.longDuration(seconds))
    }
}

// MARK: - Metric tiles

struct TodayWidget: View {
    var snapshot: DashboardSnapshot
    var body: some View {
        WidgetCard(kind: .today) {
            if let today = snapshot.today {
                MetricText(seconds: today.todaySeconds)
                let cal = snapshot.calendar
                let startOfToday = cal.startOfDay(for: Date())
                let last7 = snapshot.total(from: cal.date(byAdding: .day, value: -7, to: startOfToday)!, through: startOfToday.addingTimeInterval(-1))
                Text("7-day average \(Formatters.duration(last7 / 7))")
                    .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            } else {
                UnavailableNote(text: snapshot.failures["today"] ?? "Not loaded")
            }
        }
    }
}

struct WeekWidget: View {
    var snapshot: DashboardSnapshot
    var body: some View {
        WidgetCard(kind: .week) {
            if snapshot.failures["summaries"] != nil && snapshot.days.isEmpty {
                UnavailableNote(text: snapshot.failures["summaries"]!)
            } else {
                MetricText(seconds: snapshot.weekTotal)
                if let previous = snapshot.previousWeekTotal {
                    comparison(current: snapshot.weekTotal, previous: previous)
                }
            }
        }
    }

    @ViewBuilder private func comparison(current: Double, previous: Double) -> some View {
        if previous < 60 {
            Text(current > 0 ? "No activity by this point last week" : "Quiet week so far")
                .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
        } else {
            let change = (current - previous) / previous * 100
            HStack(spacing: 4) {
                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text("\(Formatters.percent(abs(change))) vs last week")
            }
            .font(.studioCallout)
            .foregroundStyle(change >= 0 ? Theme.ok : Theme.inkSecondary)
            .help("Compared with the same part of last week (\(Formatters.duration(previous)))")
        }
    }
}

struct MonthWidget: View {
    var snapshot: DashboardSnapshot
    var body: some View {
        WidgetCard(kind: .month) {
            if snapshot.failures["summaries"] != nil && snapshot.days.isEmpty {
                UnavailableNote(text: snapshot.failures["summaries"]!)
            } else {
                MetricText(seconds: snapshot.monthTotal)
                Text("\(snapshot.activeDaysThisMonth) active day\(snapshot.activeDaysThisMonth == 1 ? "" : "s")")
                    .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

struct StreakWidget: View {
    var snapshot: DashboardSnapshot
    var body: some View {
        WidgetCard(kind: .streak) {
            if let streak = snapshot.streak {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(streak)").font(.studioMetric).foregroundStyle(Theme.ink).contentTransition(.numericText())
                    Text(streak == 1 ? "day" : "days").font(.studioHeadline).foregroundStyle(Theme.inkSecondary)
                }
                .accessibilityElement(children: .combine)
                Text(streak > 0 ? "Keep it going today" : "Code today to start a streak")
                    .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            } else {
                UnavailableNote(text: snapshot.failures["stats.week"] ?? "Streak wasn’t included in Hackatime’s response.")
            }
        }
    }
}

// MARK: - Goal

struct GoalWidget: View {
    var snapshot: DashboardSnapshot
    var dashboardURL: URL?
    var body: some View {
        WidgetCard(kind: .goal) {
            if let goal = snapshot.today?.goal, let target = goal.targetSeconds?.value, target > 0 {
                let tracked = goal.trackedSeconds?.value ?? snapshot.today?.todaySeconds ?? 0
                let progress = min(1, tracked / target)
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Theme.ramp[0], lineWidth: 7)
                        Circle().trim(from: 0, to: progress)
                            .stroke(goal.complete == true ? Theme.ok : Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                        Text("\(Int(progress * 100))%").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    .frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.complete == true ? "Goal reached" : "\(Formatters.duration(max(0, target - tracked))) to go")
                            .font(.studioHeadline).foregroundStyle(Theme.ink)
                        Text("\(Formatters.duration(tracked)) of \(Formatters.duration(target))")
                            .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } else if snapshot.today == nil {
                UnavailableNote(text: snapshot.failures["today"] ?? "Not loaded")
            } else {
                UnavailableNote(symbol: "target", text: "No daily goal set. Weekly and custom goals aren’t available through the API.")
                if let url = dashboardURL?.appending(path: "my/settings/goals") {
                    Link("Set a goal on Hackatime", destination: url).font(.studioCallout)
                }
            }
        }
    }
}

// MARK: - Tracking status

struct TrackingWidget: View {
    var snapshot: DashboardSnapshot
    var paused: Bool
    var body: some View {
        WidgetCard(kind: .tracking) {
            if paused {
                StatusLine(status: .warning, title: "Paused", detail: "disabled = true in your config")
            }
            if let latest = snapshot.latest {
                if latest.hasHeartbeat, let hb = latest.heartbeat, let time = hb.time {
                    let age = Date().timeIntervalSince(time)
                    let status: DiagnosticCheck.Status = age < 15 * 60 ? .ok : (age < 86400 ? .info : .warning)
                    StatusLine(status: status, title: age < 15 * 60 ? "Tracking now" : "Last heartbeat",
                               detail: Formatters.relative(time))
                    Text([hb.project, hb.language, hb.editor].compactMap { $0 }.joined(separator: " · "))
                        .font(.studioCallout).foregroundStyle(Theme.inkSecondary).lineLimit(2)
                } else {
                    StatusLine(status: .warning, title: "No heartbeats yet",
                               detail: "Open a project in VS Code and edit a file.")
                }
            } else {
                UnavailableNote(text: snapshot.failures["latest"] ?? "Not loaded")
            }
        }
    }
}

// MARK: - Breakdowns

struct BreakdownWidget: View {
    var kind: WidgetKind
    var snapshot: DashboardSnapshot
    var config: WidgetConfig
    var onRangeChange: (StatsRange) -> Void

    private var items: [NamedDuration] {
        guard let stats = snapshot.stats[config.range] else { return [] }
        return kind == .languages ? stats.languages : stats.projects
    }

    var body: some View {
        WidgetCard(kind: kind) {
            Menu {
                ForEach(StatsRange.allCases) { r in
                    Button { onRangeChange(r) } label: {
                        if r == config.range { Label(r.title, systemImage: "checkmark") } else { Text(r.title) }
                    }
                }
            } label: {
                Text(config.range.title).font(.studioCaption).foregroundStyle(Theme.accent)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Change range")
        } content: {
            if snapshot.stats[config.range] == nil {
                UnavailableNote(text: snapshot.failures["stats.\(config.range.rawValue)"] ?? "Loading…")
            } else if items.isEmpty {
                UnavailableNote(symbol: "moon.zzz", text: "No coding activity in this range.")
            } else {
                content
            }
        }
    }

    private func color(_ item: NamedDuration, _ index: Int) -> Color {
        if kind == .languages, let hex = item.color { return Color(hexString: hex) }
        return kind == .projects ? Theme.accent : Theme.categorical[index % Theme.categorical.count]
    }

    @ViewBuilder private var content: some View {
        let total = items.reduce(0) { $0 + $1.totalSeconds }
        let shown = Array(items.prefix(config.limit))
        let maxValue = shown.first?.totalSeconds ?? 1
        if kind == .languages {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, item in
                        Rectangle().fill(color(item, i))
                            .frame(width: max(2, geo.size.width * item.totalSeconds / max(total, 1) - 2))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }
        VStack(spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if kind == .languages {
                            Circle().fill(color(item, i)).frame(width: 8, height: 8)
                        }
                        Text(item.name).font(.studioBody).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(Formatters.duration(item.totalSeconds)).font(.studioBody.monospacedDigit()).foregroundStyle(Theme.ink)
                        Text(Formatters.percent(item.percent ?? item.totalSeconds / max(total, 1) * 100))
                            .font(.studioCaption.monospacedDigit()).foregroundStyle(Theme.inkTertiary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    if kind == .projects {
                        GeometryReader { geo in
                            Capsule().fill(Theme.accentSoft).overlay(alignment: .leading) {
                                Capsule().fill(Theme.accent).frame(width: max(4, geo.size.width * item.totalSeconds / maxValue))
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if items.count > shown.count {
                Text("+ \(items.count - shown.count) more").font(.studioCaption).foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Recent activity

struct RecentActivityWidget: View {
    var snapshot: DashboardSnapshot

    var body: some View {
        WidgetCard(kind: .recent) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today’s sessions").font(.studioCaption).foregroundStyle(Theme.inkSecondary)
                if let spans = snapshot.spansToday {
                    timeline(spans)
                    if spans.isEmpty {
                        Text("No sessions yet today").font(.studioCallout).foregroundStyle(Theme.inkTertiary)
                    } else {
                        Text("\(spans.count) session\(spans.count == 1 ? "" : "s") · longest \(Formatters.duration(spans.map(\.duration).max() ?? 0))")
                            .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    UnavailableNote(text: snapshot.failures["spans"] ?? "Not loaded")
                }
            }
            Hairline().padding(.vertical, 2)
            let recent = snapshot.days.filter { $0.seconds > 0 }.suffix(5).reversed()
            if recent.isEmpty {
                UnavailableNote(symbol: "moon.zzz", text: "No active days in the loaded range.")
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(recent)) { day in
                        HStack(spacing: 8) {
                            Text(label(for: day.id)).font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                                .frame(width: 84, alignment: .leading)
                            Text(day.projects?.max(by: { $0.totalSeconds < $1.totalSeconds })?.name ?? "—")
                                .font(.studioBody).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Formatters.duration(day.seconds)).font(.studioBody.monospacedDigit()).foregroundStyle(Theme.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func timeline(_ spans: [ActivitySpan]) -> some View {
        let cal = snapshot.calendar
        let dayStart = cal.startOfDay(for: Date())
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ramp[0])
                ForEach(spans) { span in
                    let x = geo.size.width * CGFloat(span.start.timeIntervalSince(dayStart) / 86400)
                    let w = max(3, geo.size.width * CGFloat(span.duration / 86400))
                    Capsule().fill(Theme.accent).frame(width: w).offset(x: max(0, x))
                        .help("\(span.start.formatted(date: .omitted, time: .shortened))–\(span.end.formatted(date: .omitted, time: .shortened)) · \(Formatters.duration(span.duration))")
                }
                let nowX = geo.size.width * CGFloat(Date().timeIntervalSince(dayStart) / 86400)
                Rectangle().fill(Theme.inkTertiary).frame(width: 1, height: 14).offset(x: nowX)
            }
        }
        .frame(height: 10)
        .overlay(alignment: .bottom) {
            HStack {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { h in
                    Text(h).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.inkTertiary)
                    if h != "24" { Spacer() }
                }
            }
            .offset(y: 14)
        }
        .padding(.bottom, 14)
        .accessibilityLabel("Today’s coding sessions: \(spans.count)")
    }

    private func label(for key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = snapshot.timeZone
        guard let date = f.date(from: key) else { return key }
        let cal = snapshot.calendar
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let out = DateFormatter()
        out.timeZone = snapshot.timeZone
        out.dateFormat = "EEE d MMM"
        return out.string(from: date)
    }
}
