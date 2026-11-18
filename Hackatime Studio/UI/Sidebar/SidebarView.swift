import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection

    private struct Item: Identifiable {
        var route: Route
        var title: String
        var symbol: String
        var shortcut: String
        var id: Route { route }
    }

    private let groups: [(String, [Item])] = [
        ("Overview", [
            Item(route: .dashboard, title: "Dashboard", symbol: "square.grid.2x2", shortcut: "⌘1"),
            Item(route: .lapse, title: "Lapse", symbol: "film.stack", shortcut: "⌘6"),
        ]),
        ("Setup", [
            Item(route: .configuration, title: "Configuration", symbol: "slider.horizontal.3", shortcut: "⌘2"),
            Item(route: .folders, title: "Folders & Projects", symbol: "folder", shortcut: "⌘3"),
            Item(route: .editors, title: "Editors", symbol: "chevron.left.forwardslash.chevron.right", shortcut: "⌘4"),
        ]),
        ("System", [Item(route: .diagnostics, title: "Diagnostics", symbol: "stethoscope", shortcut: "⌘5")]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Space for the traffic lights (hidden title bar).
            Color.clear.frame(height: 40)

            wordmark
                .padding(.horizontal, 18)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.0) { title, items in
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(title).padding(.horizontal, 12).padding(.bottom, 4)
                        ForEach(items) { row($0) }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 16)

            statusCard
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            HStack(spacing: 2) {
                row(Item(route: .settings, title: "Settings", symbol: "gearshape", shortcut: "⌘,"))
                IconButton(symbol: "arrow.clockwise", label: "Refresh everything (⌘R)", spinning: model.isRefreshing) {
                    Task { await model.refreshAll() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent)
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Hackatime").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                Text("Studio").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.accent)
            }
        }
    }

    private func row(_ item: Item) -> some View {
        let selected = model.route == item.route
        return Button {
            withAnimation(Theme.Motion.selection) { model.route = item.route }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.accent : Theme.inkSecondary)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.accentSoft)
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle())
        .help("\(item.title) (\(item.shortcut))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var statusCard: some View {
        Button { model.route = .diagnostics } label: {
            HStack(spacing: 10) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(statusColor.opacity(0.35), lineWidth: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(statusDetail).font(.system(size: 11)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        }
        .buttonStyle(.plain)
        .help("Open Diagnostics")
        .accessibilityLabel("Connection: \(statusTitle). \(statusDetail)")
    }

    private var statusColor: Color {
        switch model.connection {
        case .valid: model.trackingPaused ? Theme.warning : Theme.ok
        case .invalidKey, .failed: Theme.error
        case .noKey: Theme.warning
        case .unknown, .checking: Theme.inkTertiary
        }
    }

    private var statusTitle: String {
        switch model.connection {
        case .valid(let p): p.username.map { "@\($0)" } ?? p.bestName
        case .invalidKey: "Key rejected"
        case .failed(let e): e == .offline ? "Offline" : "Can’t connect"
        case .noKey: "Not set up"
        case .unknown, .checking: "Connecting…"
        }
    }

    private var statusDetail: String {
        switch model.connection {
        case .valid: model.trackingPaused ? "Tracking paused" : "Connected to Hackatime"
        case .invalidKey: "Replace your API key"
        case .failed: "Check Diagnostics"
        case .noKey: "Add your API key"
        case .unknown, .checking: "Checking your key"
        }
    }
}

private struct SidebarRowStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering ? Theme.hairline.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
