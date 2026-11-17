import AppKit
import SwiftUI

// Colour tokens shared by the app (Theme) and the desktop widgets. Values come from DESIGN.md.
// Light and dark are designed separately (not inverted).

/// A light/dark colour pair. The app uses `dynamic` (resolved by AppKit per appearance); widgets
/// resolve explicitly with `color(for:)`, because WidgetKit archives views ahead of rendering.
nonisolated struct Tone: Sendable {
    var light: UInt32
    var dark: UInt32
    var lightAlpha: Double = 1
    var darkAlpha: Double = 1

    var dynamic: Color { Color(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha) }

    func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: dark, opacity: darkAlpha) : Color(hex: light, opacity: lightAlpha)
    }
}

nonisolated enum Palette {
    // Surfaces
    static let canvas = Tone(light: 0xF3F5F9, dark: 0x0E1116)
    static let sidebar = Tone(light: 0xEAEEF5, dark: 0x12161D)
    static let panel = Tone(light: 0xFFFFFF, dark: 0x181C24)
    static let panelRaised = Tone(light: 0xF7F9FC, dark: 0x1F2430)
    static let hairline = Tone(light: 0x0F172A, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.06)
    static let highlight = Tone(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0, darkAlpha: 0.04)

    // Ink
    static let ink = Tone(light: 0x0F172A, dark: 0xE8ECF4)
    static let inkSecondary = Tone(light: 0x475569, dark: 0xA3ADBF)
    static let inkTertiary = Tone(light: 0x8591A5, dark: 0x6B7588)

    // Accent — Signal Blue
    static let accent = Tone(light: 0x1D5BF0, dark: 0x6B97FF)
    static let accentSoft = Tone(light: 0x1D5BF0, dark: 0x6B97FF, lightAlpha: 0.11, darkAlpha: 0.16)
    static let accentInk = Tone(light: 0xFFFFFF, dark: 0x0B1020)

    // Status
    static let ok = Tone(light: 0x13A26B, dark: 0x3DD598)
    static let warning = Tone(light: 0xC98200, dark: 0xF5B83D)
    static let error = Tone(light: 0xD64045, dark: 0xFF6B6E)

    /// Activity ramp, index 0 = no activity.
    static let ramp: [Tone] = [
        Tone(light: 0xE6EBF3, dark: 0x1C222D),
        Tone(light: 0xBFD2FF, dark: 0x1E3366),
        Tone(light: 0x85A9FF, dark: 0x2A4FA8),
        Tone(light: 0x3D74F5, dark: 0x4677F0),
        Tone(light: 0x1A4CC9, dark: 0x86A9FF),
    ]
}

extension Color {
    nonisolated init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    nonisolated init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x64748B
        self.init(nsColor: NSColor(hex: v, alpha: 1))
    }
}

extension NSColor {
    nonisolated convenience init(hex: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
