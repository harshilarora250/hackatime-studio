import AppKit
import SwiftUI

// Tokens defined in DESIGN.md; colour values live in Shared/Palette.swift (shared with the widgets).

enum Theme {
    // Surfaces
    static let canvas = Palette.canvas.dynamic
    static let sidebar = Palette.sidebar.dynamic
    static let panel = Palette.panel.dynamic
    static let panelRaised = Palette.panelRaised.dynamic
    static let hairline = Palette.hairline.dynamic
    static let highlight = Palette.highlight.dynamic

    // Ink
    static let ink = Palette.ink.dynamic
    static let inkSecondary = Palette.inkSecondary.dynamic
    static let inkTertiary = Palette.inkTertiary.dynamic

    // Accent — Signal Blue
    static let accent = Palette.accent.dynamic
    static let accentSoft = Palette.accentSoft.dynamic
    static let accentInk = Palette.accentInk.dynamic

    // Status
    static let ok = Palette.ok.dynamic
    static let warning = Palette.warning.dynamic
    static let error = Palette.error.dynamic

    /// Activity ramp, index 0 = no activity.
    static let ramp: [Color] = Palette.ramp.map(\.dynamic)

    static let categorical: [Color] = [
        accent, Color(hexString: "#14A3B8"), Color(hexString: "#7C5CFF"),
        Color(hexString: "#E5A13A"), Color(hexString: "#E2557B"), Color(hexString: "#64748B"),
    ]

    enum Radius {
        static let panel: CGFloat = 16
        static let well: CGFloat = 10
        static let button: CGFloat = 8
        static let chip: CGFloat = 6
        static let cell: CGFloat = 3
    }

    enum Space {
        static let xxs: CGFloat = 4, xs: CGFloat = 8, s: CGFloat = 12, m: CGFloat = 16
        static let l: CGFloat = 20, xl: CGFloat = 24, xxl: CGFloat = 32, xxxl: CGFloat = 40
        static let pageH: CGFloat = 28
        static let panelPadding: CGFloat = 18
    }

    enum Motion {
        static let selection = Animation.spring(response: 0.32, dampingFraction: 0.86)
        static let page = Animation.easeOut(duration: 0.18)
        static let hover = Animation.easeOut(duration: 0.12)
        static let appear = Animation.easeOut(duration: 0.2)
    }
}

extension Font {
    static let studioMetric = Font.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()
    static let studioMetricSmall = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    static let studioPageTitle = Font.system(size: 22, weight: .bold)
    static let studioHeadline = Font.system(size: 14, weight: .semibold)
    static let studioBody = Font.system(size: 13)
    static let studioCallout = Font.system(size: 12)
    static let studioCaption = Font.system(size: 11, weight: .medium)
    static let studioEyebrow = Font.system(size: 10.5, weight: .semibold)
    static let studioCode = Font.system(size: 11.5, weight: .medium, design: .monospaced)
}

extension DiagnosticCheck.Status {
    var color: Color {
        switch self {
        case .ok: Theme.ok
        case .warning: Theme.warning
        case .error: Theme.error
        case .info: Theme.accent
        case .unknown: Theme.inkTertiary
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .ok: "OK"
        case .warning: "Warning"
        case .error: "Problem"
        case .info: "Info"
        case .unknown: "Not verified"
        }
    }
}
