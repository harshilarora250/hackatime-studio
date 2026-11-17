import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let checks = model.diagnostics
        Page {
            PageHeader(title: "Diagnostics", subtitle: "Each layer is checked separately — a config file existing doesn’t mean tracking works.") {
                HStack(spacing: 8) {
                    Button { Pasteboard.copy(report(checks)); model.toast = Toast(message: "Report copied (API key removed)", style: .info) } label: {
                        Label("Copy report", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.studioSecondary)
                    Button { Task { await model.runDiagnostics() } } label: {
                        if model.isRunningDiagnostics {
                            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Running…") }
                        } else {
                            Label("Run diagnostics", systemImage: "stethoscope")
                        }
                    }
                    .buttonStyle(.studioPrimary)
                    .disabled(model.isRunningDiagnostics)
                }
            }

            pillars(checks)

            ForEach(DiagnosticCheck.Group.allCases, id: \.self) { group in
                let items = checks.filter { $0.group == group }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: group.rawValue, subtitle: group.subtitle)
                        Panel {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { i, check in
                                    CheckRow(check: check)
                                    if i < items.count - 1 { Hairline() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The four distinctions the user cares about, at a glance.
    private func pillars(_ checks: [DiagnosticCheck]) -> some View {
        let groups: [(DiagnosticCheck.Group, String)] = [
            (.configuration, "Config valid"), (.connection, "API working"),
            (.editor, "Editor installed"), (.activity, "Heartbeats received"),
        ]
        return HStack(spacing: 12) {
            ForEach(groups, id: \.0) { group, title in
                let status = worst(checks.filter { $0.group == group })
                Panel(padding: 14) {
                    HStack(spacing: 10) {
                        StatusGlyph(status: status, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.studioBody.weight(.semibold))
                            Text(status.label).font(.studioCaption).foregroundStyle(status.color)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func worst(_ checks: [DiagnosticCheck]) -> DiagnosticCheck.Status {
        let relevant = checks.map(\.status).filter { $0 != .info }
        if relevant.isEmpty { return checks.isEmpty ? .unknown : .ok }
        if relevant.allSatisfy({ $0 == .unknown }) { return .unknown }
        return relevant.filter { $0 != .unknown }.max() ?? .unknown
    }

    private func report(_ checks: [DiagnosticCheck]) -> String {
        var lines = ["Hackatime Studio diagnostics — \(Date().formatted())",
                     "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", ""]
        for group in DiagnosticCheck.Group.allCases {
            lines.append("## \(group.rawValue)")
            for c in checks where c.group == group {
                lines.append("[\(c.status.label)] \(c.title)\(c.detail.isEmpty ? "" : " — \(c.detail)")")
            }
            lines.append("")
        }
        return Redaction.redactSecrets(in: lines.joined(separator: "\n"), knownSecrets: [model.apiKey].compactMap { $0 })
    }
}

private struct CheckRow: View {
    var check: DiagnosticCheck
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusLine(status: check.status, title: check.title, detail: check.detail)
            Spacer(minLength: 12)
            if let fix = check.fix, let title = check.fixTitle {
                Button(title) { model.perform(fix) }
                    .buttonStyle(.studio(check.status >= .warning ? .primary : .secondary, compact: true))
            }
        }
        .padding(.vertical, 10)
    }
}
