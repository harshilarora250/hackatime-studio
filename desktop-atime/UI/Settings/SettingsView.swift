import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var customizing = false
    @State private var uninstallMode: UninstallMode?

    var body: some View {
        @Bindable var model = model
        Page {
            PageHeader(title: "Settings", subtitle: "Preferences for Hackatime Studio itself. These aren’t stored in your WakaTime config.")

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Appearance & refresh")
                Panel {
                    VStack(spacing: 0) {
                        row("Appearance", "Follow the system, or always use light or dark.") {
                            ChipPicker(options: AppearancePreference.allCases.map { ($0, $0.title) }, selection: $model.appearance)
                        }
                        Hairline()
                        row("Refresh dashboard", "Automatic refresh only runs while Studio is in front. ⌘R always refreshes everything.") {
                            Picker("Refresh", selection: $model.refreshInterval) {
                                ForEach(RefreshInterval.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Dashboard & setup")
                Panel {
                    VStack(spacing: 0) {
                        row("Dashboard widgets", "\(model.layout.visible.count) of \(model.layout.widgets.count) shown.") {
                            HStack {
                                Button("Restore defaults") { model.layout = .default; Task { await model.refreshDashboard() } }.buttonStyle(.studioQuiet)
                                Button("Customize…") { customizing = true }.buttonStyle(.studioSecondary)
                            }
                        }
                        Hairline()
                        row("Guided setup", "Walk through editor, folders, privacy and dashboard setup again.") {
                            Button("Start") { model.setupFlow = model.apiKey == nil ? .enterKey : .guided(0) }.buttonStyle(.studioSecondary)
                        }
                        Hairline()
                        row("Config backups", "Copies saved before each change Studio makes.") {
                            Button("Show in Finder") { model.perform(.reveal(StudioPaths.backupsDirectory)) }.buttonStyle(.studioSecondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Remove tracking", subtitle: "Hackatime Studio stays installed either way. You’ll see exactly what will be removed before anything happens.")
                HStack(alignment: .top, spacing: 16) {
                    ForEach(UninstallMode.allCases) { mode in
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: mode == .studioManaged ? "arrow.uturn.backward.circle" : "trash.circle")
                                    .font(.system(size: 22)).foregroundStyle(mode == .studioManaged ? Theme.accent : Theme.error)
                                Text(mode.title).font(.studioHeadline)
                                Text(mode.summary).font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button("Review…") { uninstallMode = mode }
                                    .buttonStyle(.studio(mode == .studioManaged ? .secondary : .destructive))
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Hackatime Studio \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · a GUI for Hackatime and wakatime-cli")
                Spacer()
                Link("Hackatime docs", destination: URL(string: "https://hackatime.hackclub.com/docs")!)
            }
            .font(.studioCaption).foregroundStyle(Theme.inkTertiary)
        }
        .sheet(isPresented: $customizing) { CustomizeDashboardSheet() }
        .sheet(item: $uninstallMode) { UninstallSheet(mode: $0) }
    }

    private func row<Control: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.studioBody.weight(.medium))
                Text(detail).font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
        }
        .padding(.vertical, 10)
    }
}

struct UninstallSheet: View {
    var mode: UninstallMode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var plan: UninstallPlan?
    @State private var confirmText = ""
    @State private var running = false
    @State private var outcomes: [UninstallOutcome]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title).font(.system(size: 17, weight: .bold))
                Text(mode.summary).font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let outcomes {
                        resultView(outcomes)
                    } else if let plan {
                        planView(plan)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .frame(minHeight: 260, maxHeight: 440)

            Hairline()
            footer.padding(16)
        }
        .frame(width: 600)
        .background(Theme.panel)
        .task {
            await model.refreshEditors()
            await model.refreshInstallation(runCLICheck: false)
            plan = model.uninstallPlan(mode)
        }
    }

    @ViewBuilder private func planView(_ plan: UninstallPlan) -> some View {
        if plan.isEmpty {
            UnavailableNote(symbol: "checkmark.circle", text: plan.warnings.first ?? "Nothing to remove was detected.")
        }
        ForEach(plan.warnings.filter { !plan.isEmpty || $0 != plan.warnings.first }, id: \.self) { w in
            StatusLine(status: .warning, title: w)
        }
        ForEach(Binding(get: { self.plan?.items ?? [] }, set: { self.plan?.items = $0 })) { $item in
            HStack(alignment: .top, spacing: 10) {
                if item.isRemovable {
                    Toggle(item.title, isOn: $item.isSelected).labelsHidden().toggleStyle(.checkbox)
                } else {
                    Image(systemName: "hand.raised").foregroundStyle(Theme.inkTertiary).frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.studioBody.weight(.medium)).foregroundStyle(item.isRemovable ? Theme.ink : Theme.inkSecondary)
                    Text(item.detail).font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous))
        }
        if mode == .everything && !plan.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Type REMOVE to confirm").font(.studioCallout.weight(.medium))
                TextField("REMOVE", text: $confirmText).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            .padding(.top, 4)
        }
    }

    private func resultView(_ outcomes: [UninstallOutcome]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if outcomes.isEmpty {
                UnavailableNote(text: "Nothing was selected, so nothing changed.")
            }
            ForEach(outcomes) { o in
                StatusLine(status: o.succeeded ? .ok : .error, title: o.title, detail: o.message)
            }
            if outcomes.contains(where: { !$0.succeeded }) {
                Text("Some steps failed. Everything else was completed; nothing was rolled back. You can retry or remove the remaining items manually.")
                    .font(.studioCallout).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if outcomes == nil {
                Button("Cancel") { dismiss() }.buttonStyle(.studioSecondary).keyboardShortcut(.cancelAction)
                Spacer()
                let selected = plan?.items.filter { $0.isSelected && $0.isRemovable }.count ?? 0
                Button {
                    guard let plan else { return }
                    running = true
                    Task {
                        outcomes = await model.execute(plan)
                        running = false
                    }
                } label: {
                    if running { HStack { ProgressView().controlSize(.mini); Text("Removing…") } }
                    else { Text(selected == 0 ? "Nothing selected" : "Remove \(selected) item\(selected == 1 ? "" : "s")") }
                }
                .buttonStyle(.studio(.destructiveSolid))
                .disabled(selected == 0 || running || (mode == .everything && confirmText != "REMOVE"))
            } else {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.studioPrimary).keyboardShortcut(.defaultAction)
            }
        }
    }
}
