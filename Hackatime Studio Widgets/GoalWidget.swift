import SwiftUI
import WidgetKit

struct GoalWidget: Widget {
    let kind = "xyz.elipseday.hackatime-studio.goal"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StudioProvider()) { entry in
            GoalWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Daily Goal")
        .description("Progress toward your Hackatime daily coding goal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GoalWidgetView: View {
    var entry: StudioEntry
    @Environment(\.widgetFamily) private var family

    private var isSmall: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: isSmall ? 6 : 10) {
            WidgetHeader(symbol: "target", title: "Daily goal")
            if let snapshot = entry.snapshot {
                if let goal = snapshot.goal(at: entry.date) {
                    if isSmall { small(goal, snapshot: snapshot) } else { medium(goal, snapshot: snapshot) }
                } else {
                    noGoal
                }
            } else {
                OpenStudioNote()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func small(_ goal: WidgetSnapshot.Goal, snapshot: WidgetSnapshot) -> some View {
        Styled { style in
            VStack(spacing: 8) {
                GoalRing(goal: goal, lineWidth: 8, percentSize: 19)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(headline(goal))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(goal.isComplete ? style.ok : style.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility(goal))
        }
    }

    private func medium(_ goal: WidgetSnapshot.Goal, snapshot: WidgetSnapshot) -> some View {
        Styled { style in
            HStack(spacing: 18) {
                GoalRing(goal: goal, lineWidth: 9, percentSize: 20)
                    .frame(maxWidth: 104, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(goal))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(goal.isComplete ? style.ok : style.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(Formatters.duration(goal.trackedSeconds)) of \(Formatters.duration(goal.targetSeconds))")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(style.inkSecondary)
                    if snapshot.isStale(at: entry.date) {
                        StaleNote(fetchedAt: snapshot.fetchedAt, now: entry.date).padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility(goal))
        }
    }

    private var noGoal: some View {
        Styled { style in
            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 0)
                Text("No daily goal set")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.ink)
                Text("Set one in your Hackatime settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(style.inkTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    private func headline(_ goal: WidgetSnapshot.Goal) -> String {
        goal.isComplete ? "Goal reached" : "\(Formatters.duration(goal.remainingSeconds)) to go"
    }

    private func accessibility(_ goal: WidgetSnapshot.Goal) -> String {
        "Daily goal, \(goal.percent) percent. \(Formatters.longDuration(goal.trackedSeconds)) of \(Formatters.longDuration(goal.targetSeconds))."
    }
}

/// Progress ring with the percentage in the middle (matches the dashboard's goal card).
struct GoalRing: View {
    var goal: WidgetSnapshot.Goal
    var lineWidth: CGFloat
    var percentSize: CGFloat

    var body: some View {
        Styled { style in
            ZStack {
                Circle()
                    .stroke(style.track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, goal.fraction))
                    .stroke(goal.isComplete ? style.ok : style.accent,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(goal.trackedSeconds > 0 ? 1 : 0)
                    .widgetAccentable()
                if goal.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: percentSize, weight: .bold))
                        .foregroundStyle(style.ok)
                        .widgetAccentable()
                } else {
                    Text("\(goal.percent)%")
                        .font(.system(size: percentSize, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(style.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .padding(lineWidth / 2)
            .aspectRatio(1, contentMode: .fit)
        }
    }
}

#Preview("Small", as: .systemSmall) {
    GoalWidget()
} timeline: {
    StudioEntry(date: .now, snapshot: .sample())
}

#Preview("Medium", as: .systemMedium) {
    GoalWidget()
} timeline: {
    StudioEntry(date: .now, snapshot: .sample())
}
