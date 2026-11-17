import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var customizing = false

    var body: some View {
        Page {
            PageHeader(title: greeting, subtitle: subtitle) {
                HStack(spacing: 8) {
                    if model.isLoadingDashboard { ProgressView().controlSize(.small) }
                    Button { customizing = true } label: { Label("Customize", systemImage: "square.grid.2x2") }
                        .buttonStyle(.studioSecondary)
                    Button { Task { await model.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(.studioSecondary)
                        .help("Refresh everything (⌘R)")
                }
            }

            banner

            if let snapshot = model.snapshot {
                WidgetGrid {
                    ForEach(model.layout.visible) { config in
                        widget(config, snapshot: snapshot)
                            .gridSpan(config.kind.span.rawValue)
                            .studioAppear()
                    }
                }
                if model.layout.visible.isEmpty {
                    Panel {
                        UnavailableNote(symbol: "square.grid.2x2", text: "All widgets are hidden. Use Customize to add some back.")
                    }
                }
            } else if model.connection.isValid || model.connection == .checking {
                Panel {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading your Hackatime data…").font(.studioBody).foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $customizing) { CustomizeDashboardSheet() }
    }

    private var greeting: String {
        if let name = model.connection.profile?.displayName ?? model.connection.profile?.username {
            return "Hey, \(name.components(separatedBy: " ").first ?? name)"
        }
        return "Dashboard"
    }

    private var subtitle: String {
        guard let snap = model.snapshot else { return "Your coding time from Hackatime" }
        return "Updated \(Formatters.relative(snap.fetchedAt)) · times in \(snap.timeZone.identifier)"
    }

    @ViewBuilder private var banner: some View {
        switch model.connection {
        case .noKey:
            callout(.warning, "Hackatime isn’t connected", "Add your API key to load your stats.", "Set up") { model.setupFlow = .enterKey }
        case .invalidKey:
            callout(.error, "Hackatime rejected your API key", "The key in \(model.location.displayPath) may have been rotated. Your config hasn’t been changed.", "Replace key") { model.route = .configuration }
        case .failed(let e):
            callout(.error, "Can’t reach Hackatime", e.errorDescription ?? "", "Diagnostics") { model.route = .diagnostics }
        default:
            if let error = model.dashboardError {
                callout(.warning, "Some data couldn’t be loaded", error, "Retry") { Task { await model.refreshDashboard() } }
            }
        }
    }

    private func callout(_ status: DiagnosticCheck.Status, _ title: String, _ detail: String, _ action: String, perform: @escaping () -> Void) -> some View {
        Panel(padding: 14) {
            HStack(spacing: 12) {
                StatusLine(status: status, title: title, detail: detail)
                Spacer(minLength: 12)
                Button(action, action: perform).buttonStyle(.studioPrimary)
            }
        }
    }

    @ViewBuilder
    private func widget(_ config: WidgetConfig, snapshot: DashboardSnapshot) -> some View {
        switch config.kind {
        case .today: TodayWidget(snapshot: snapshot)
        case .week: WeekWidget(snapshot: snapshot)
        case .month: MonthWidget(snapshot: snapshot)
        case .streak: StreakWidget(snapshot: snapshot)
        case .goal: GoalWidget(snapshot: snapshot, dashboardURL: model.endpoints?.dashboardURL)
        case .tracking: TrackingWidget(snapshot: snapshot, paused: model.trackingPaused)
        case .recent: RecentActivityWidget(snapshot: snapshot)
        case .activity:
            WidgetCard(kind: .activity, subtitle: "last \(config.weeks) weeks") {
                if snapshot.days.isEmpty, let error = snapshot.failures["summaries"] {
                    UnavailableNote(text: error)
                } else {
                    ActivityGraph(snapshot: snapshot, weeks: min(max(config.weeks, 4), 52))
                }
            }
        case .languages, .projects:
            BreakdownWidget(kind: config.kind, snapshot: snapshot, config: config) { range in
                update(config.kind) { $0.range = range }
                Task { await model.refreshDashboard() }
            }
        }
    }

    private func update(_ kind: WidgetKind, _ change: (inout WidgetConfig) -> Void) {
        guard let i = model.layout.widgets.firstIndex(where: { $0.kind == kind }) else { return }
        change(&model.layout.widgets[i])
    }
}

struct CustomizeDashboardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Customize dashboard").font(.studioHeadline)
                        Text("Show, hide and drag to reorder. Changes apply immediately.").font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    Button("Restore defaults") {
                        withAnimation { model.layout = .default }
                        Task { await model.refreshDashboard() }
                    }
                    .buttonStyle(.studioSecondary)
                }
                .padding(20)
                Hairline()
            }
            List {
                ForEach($model.layout.widgets) { $config in
                    WidgetConfigRow(config: $config)
                }
                .onMove { from, to in model.layout.widgets.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minHeight: embedded ? 360 : 420)
            if !embedded {
                Hairline()
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                        Task { await model.refreshDashboard() }
                    }
                    .buttonStyle(.studioPrimary)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
        }
        .frame(width: embedded ? nil : 560)
        .background(Theme.panel)
    }
}

private struct WidgetConfigRow: View {
    @Binding var config: WidgetConfig

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "line.3.horizontal").foregroundStyle(Theme.inkTertiary).padding(.top, 3)
                .accessibilityHidden(true)
            Image(systemName: config.kind.symbol).frame(width: 18).foregroundStyle(config.isVisible ? Theme.accent : Theme.inkTertiary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(config.kind.title).font(.studioBody.weight(.medium))
                Text(config.kind.summary).font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                if config.isVisible && (config.kind.supportsRange || config.kind.supportsWeeks) {
                    HStack(spacing: 12) {
                        if config.kind.supportsRange {
                            Picker("Range", selection: $config.range) {
                                ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
                            }
                            .fixedSize()
                            Stepper("Show \(config.limit)", value: $config.limit, in: 3...15)
                                .fixedSize()
                        }
                        if config.kind.supportsWeeks {
                            Picker("Length", selection: $config.weeks) {
                                Text("3 months").tag(13)
                                Text("6 months").tag(26)
                                Text("12 months").tag(52)
                            }
                            .fixedSize()
                        }
                    }
                    .controlSize(.small)
                    .font(.studioCallout)
                    .padding(.top, 2)
                }
            }
            Spacer()
            Toggle("Show \(config.kind.title)", isOn: $config.isVisible.animation())
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}
