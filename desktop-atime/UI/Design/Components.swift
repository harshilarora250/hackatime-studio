import AppKit
import SwiftUI

// MARK: - Panel

/// The primary surface. Light: hairline stroke. Dark: top highlight, no stroke. Never shadows.
struct Panel<Content: View>: View {
    var padding: CGFloat = Theme.Space.panelPadding
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(scheme == .dark
                                  ? AnyShapeStyle(LinearGradient(colors: [Theme.highlight, .clear], startPoint: .top, endPoint: .center))
                                  : AnyShapeStyle(Theme.hairline), lineWidth: 1)
            }
    }
}

/// Eyebrow + optional trailing accessory, placed above a panel.
struct SectionHeader<Accessory: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(title)
                if let subtitle {
                    Text(subtitle).font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
            accessory
        }
        .padding(.horizontal, 2)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct Eyebrow: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.studioEyebrow)
            .tracking(0.8)
            .foregroundStyle(Theme.inkTertiary)
    }
}

// MARK: - Key tag

/// Shows the real config key a control writes — a signature element of Studio.
struct KeyTag: View {
    var key: String
    var section: String = "settings"
    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .help("[\(section)] \(key)")
            .accessibilityLabel("Config key \(key) in section \(section)")
    }
}

// MARK: - Status

struct StatusGlyph: View {
    var status: DiagnosticCheck.Status
    var size: CGFloat = 13
    var body: some View {
        Image(systemName: status.symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(status.color)
            .accessibilityLabel(status.label)
    }
}

struct StatusLine: View {
    var status: DiagnosticCheck.Status
    var title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            StatusGlyph(status: status)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.studioBody.weight(.medium)).foregroundStyle(Theme.ink)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A muted explanation used instead of fake zeros when data isn't available.
struct UnavailableNote: View {
    var symbol: String = "questionmark.circle"
    var text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.inkTertiary)
            Text(text).font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Buttons

struct StudioButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive, destructiveSolid }
    var kind: Kind = .secondary
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, kind == .quiet ? 6 : (compact ? 10 : 14))
            .frame(height: compact ? 26 : 30)
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).strokeBorder(Theme.hairline)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
            .animation(Theme.Motion.hover, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.accentInk
        case .secondary: Theme.ink
        case .quiet: Theme.accent
        case .destructive: Theme.error
        case .destructiveSolid: .white
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: Theme.accent.opacity(pressed ? 0.85 : (hovering ? 0.92 : 1))
        case .secondary: hovering ? Theme.accentSoft : Theme.panelRaised
        case .quiet: hovering ? Theme.accentSoft : .clear
        case .destructive: Theme.error.opacity(hovering ? 0.14 : 0.08)
        case .destructiveSolid: Theme.error.opacity(pressed ? 0.85 : 1)
        }
    }
}

extension ButtonStyle where Self == StudioButtonStyle {
    static var studioPrimary: StudioButtonStyle { StudioButtonStyle(kind: .primary) }
    static var studioSecondary: StudioButtonStyle { StudioButtonStyle(kind: .secondary) }
    static var studioQuiet: StudioButtonStyle { StudioButtonStyle(kind: .quiet) }
    static var studioDestructive: StudioButtonStyle { StudioButtonStyle(kind: .destructive) }
    static func studio(_ kind: StudioButtonStyle.Kind, compact: Bool = false) -> StudioButtonStyle {
        StudioButtonStyle(kind: kind, compact: compact)
    }
}

/// Icon-only circular button with tooltip and accessibility label.
struct IconButton: View {
    var symbol: String
    var label: String
    var spinning = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 28, height: 28)
                .foregroundStyle(hovering ? Theme.accent : Theme.inkSecondary)
                .background(hovering ? Theme.accentSoft : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Segmented chips

struct ChipPicker<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Button {
                    withAnimation(Theme.Motion.selection) { selection = value }
                } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.accent : Theme.inkSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.panel)
                                    .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "chip", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - Page scaffolding

struct PageHeader<Actions: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.studioPageTitle).foregroundStyle(Theme.ink)
                Text(subtitle).font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
            actions
        }
    }
}

extension PageHeader where Actions == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    /// Debug snapshot captures can't see inside NSScrollView, so snapshots lay pages out flat.
    private static var flat: Bool { ProcessInfo.processInfo.environment["STUDIO_SNAPSHOT_DIR"] != nil }

    private var stack: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            content
        }
        .padding(.horizontal, Theme.Space.pageH)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.xxxl)
        .frame(maxWidth: 1180, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        if Self.flat {
            Color.clear.overlay(alignment: .top) { stack.fixedSize(horizontal: false, vertical: true) }.clipped()
        } else {
            ScrollView { stack }
                .scrollContentBackground(.hidden)
        }
    }
}

/// A raised inner well used to seat native inputs inside panels.
struct Well<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// A thin divider using the single hairline token.
struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

// MARK: - Toast

struct ToastView: View {
    var toast: Toast
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(toast.message).font(.studioBody).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let undo = toast.undo {
                Button("Undo") { undo(); dismiss() }.buttonStyle(.studio(.quiet, compact: true))
            }
            IconButton(symbol: "xmark", label: "Dismiss", action: dismiss)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: 560)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    private var icon: String {
        switch toast.style {
        case .success: "checkmark.circle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    private var color: Color {
        switch toast.style {
        case .success: Theme.ok
        case .error: Theme.error
        case .info: Theme.accent
        }
    }
}

// MARK: - Helpers

extension View {
    /// Fade + slight lift when appearing; respects Reduce Motion.
    func studioAppear(delay: Double = 0) -> some View { modifier(AppearModifier(delay: delay)) }
}

private struct AppearModifier: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.985)
            .onAppear { withAnimation(Theme.Motion.appear.delay(delay)) { shown = true } }
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    static var string: String? { NSPasteboard.general.string(forType: .string) }
}

enum FilePicker {
    @MainActor
    static func chooseFolder(message: String, multiple: Bool = false) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = multiple
        panel.canCreateDirectories = false
        panel.message = message
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.urls : []
    }

    @MainActor
    static func chooseFile(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}
