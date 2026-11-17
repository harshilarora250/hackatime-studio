import AppKit
import SwiftUI

// Tokens defined in DESIGN.md. Light and dark are designed separately (not inverted).

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x64748B
        self.init(nsColor: NSColor(hex: v, alpha: 1))
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum Theme {
    // Surfaces
    static let canvas = Color(light: 0xF3F5F9, dark: 0x0E1116)
    static let sidebar = Color(light: 0xEAEEF5, dark: 0x12161D)
    static let panel = Color(light: 0xFFFFFF, dark: 0x181C24)
    static let panelRaised = Color(light: 0xF7F9FC, dark: 0x1F2430)
    static let hairline = Color(light: 0x0F172A, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.06)
    static let highlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0, darkAlpha: 0.04)

    // Ink
    static let ink = Color(light: 0x0F172A, dark: 0xE8ECF4)
    static let inkSecondary = Color(light: 0x475569, dark: 0xA3ADBF)
    static let inkTertiary = Color(light: 0x8591A5, dark: 0x6B7588)

    // Accent — Signal Blue
    static let accent = Color(light: 0x1D5BF0, dark: 0x6B97FF)
    static let accentSoft = Color(light: 0x1D5BF0, dark: 0x6B97FF, lightAlpha: 0.11, darkAlpha: 0.16)
    static let accentInk = Color(light: 0xFFFFFF, dark: 0x0B1020)

    // Status
    static let ok = Color(light: 0x13A26B, dark: 0x3DD598)
    static let warning = Color(light: 0xC98200, dark: 0xF5B83D)
    static let error = Color(light: 0xD64045, dark: 0xFF6B6E)

    /// Activity ramp, index 0 = no activity.
    static let ramp: [Color] = [
        Color(light: 0xE6EBF3, dark: 0x1C222D),
        Color(light: 0xBFD2FF, dark: 0x1E3366),
        Color(light: 0x85A9FF, dark: 0x2A4FA8),
        Color(light: 0x3D74F5, dark: 0x4677F0),
        Color(light: 0x1A4CC9, dark: 0x86A9FF),
    ]

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
