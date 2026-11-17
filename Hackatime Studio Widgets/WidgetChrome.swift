import SwiftUI
import WidgetKit

/// Resolves the shared palette for the current widget appearance. In the desktop's tinted /
/// vibrant modes colours are replaced by primary-opacity steps so the system can recolour them.
struct WidgetStyle {
    var scheme: ColorScheme
    var mode: WidgetRenderingMode

    var isFullColor: Bool { mode == .fullColor }

    func callAsFunction(_ tone: Tone) -> Color { tone.color(for: scheme) }

    func ramp(_ level: Int) -> Color {
        if isFullColor { return Palette.ramp[level].color(for: scheme) }
        return Color.primary.opacity([0.12, 0.32, 0.52, 0.76, 1][level])
    }

    var ink: Color { isFullColor ? self(Palette.ink) : .primary }
    var inkSecondary: Color { isFullColor ? self(Palette.inkSecondary) : .secondary }
    var inkTertiary: Color { isFullColor ? self(Palette.inkTertiary) : .secondary }
    var accent: Color { isFullColor ? self(Palette.accent) : .primary }
    var ok: Color { isFullColor ? self(Palette.ok) : .primary }
    var track: Color { isFullColor ? Palette.ramp[0].color(for: scheme) : Color.primary.opacity(0.15) }
}

private struct WidgetStyleReader<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    @ViewBuilder var content: (WidgetStyle) -> Content
    var body: some View { content(WidgetStyle(scheme: scheme, mode: mode)) }
}

/// Convenience: `Styled { style in … }`.
struct Styled<Content: View>: View {
    @ViewBuilder var content: (WidgetStyle) -> Content
    var body: some View { WidgetStyleReader(content: content) }
}

/// The panel colour from the app, so widgets look like dashboard cards.
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Palette.panel.color(for: scheme) }
}

/// "▦ CODING ACTIVITY  last 16 weeks" — the dashboard card eyebrow.
struct WidgetHeader: View {
    var symbol: String
    var title: String
    var detail: String?

    var body: some View {
        Styled { style in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(style.inkSecondary)
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(style.inkSecondary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(style.inkTertiary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Shown when the snapshot is older than `WidgetSnapshot.staleAfter`.
struct StaleNote: View {
    var fetchedAt: Date
    var now: Date

    var body: some View {
        Styled { style in
            Label(text, systemImage: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(style.inkTertiary)
                .lineLimit(1)
        }
    }

    private var text: String {
        let calendar = Calendar.current
        let f = DateFormatter()
        if calendar.isDate(fetchedAt, inSameDayAs: now) {
            f.timeStyle = .short
        } else {
            f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        }
        return "Updated \(f.string(from: fetchedAt))"
    }
}

/// Before the app has ever refreshed.
struct OpenStudioNote: View {
    var body: some View {
        Styled { style in
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(style.accent)
                Text("Open Hackatime Studio to load your stats.")
                    .font(.system(size: 11.5, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(style.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
