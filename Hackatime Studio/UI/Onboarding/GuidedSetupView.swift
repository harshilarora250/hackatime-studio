import SwiftUI

/// Optional walkthrough after the key is saved. Every step writes real config immediately and
/// can be skipped.
struct GuidedSetupView: View {
    var step: Int
    @Environment(AppModel.self) private var model

    private let steps = ["Editor", "Folders", "Tracking & privacy", "Dashboard"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, title in
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(i <= step ? Theme.accent : Theme.panelRaised)
                            if i < step {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accentInk)
                            } else {
                                Text("\(i + 1)").font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(i == step ? Theme.accentInk : Theme.inkTertiary)
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(title).font(.studioCallout.weight(i == step ? .semibold : .regular))
                            .foregroundStyle(i == step ? Theme.ink : Theme.inkSecondary)
                    }
                    if i < steps.count - 1 { Rectangle().fill(Theme.hairline).frame(width: 24, height: 1) }
                }
            }
            .padding(.top, 48).padding(.bottom, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(steps.count): \(steps[step])")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }

            Hairline()
            HStack {
                if step > 0 {
                    Button("Back") { go(step - 1) }.buttonStyle(.studioSecondary)
                }
                Spacer()
                Button("Skip") { go(step + 1) }.buttonStyle(.studioQuiet)
                Button(step == steps.count - 1 ? "Finish" : "Continue") { go(step + 1) }
                    .buttonStyle(.studioPrimary).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36).padding(.vertical, 16)
            .frame(maxWidth: 820)
        }
    }

    private func go(_ next: Int) {
        if next >= steps.count {
            model.route = .dashboard
            model.finishSetup()
            Task { await model.refreshDashboard() }
        } else {
            withAnimation(Theme.Motion.page) { model.setupFlow = .guided(max(0, next)) }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            heading("Connect VS Code", "Studio checks what’s installed. Installing only happens when you click Install.")
            EditorsStep()
        case 1:
            heading("Where do you code?", "Add your working folders and choose how each should become projects. You can change this anytime in Folders & Projects.")
            FoldersStep()
        case 2:
            heading("Tracking & privacy", "These are optional. Defaults work well for Hack Club programmes, which need file names to verify work.")
            Panel {
                VStack(spacing: 0) {
                    OptionRow(option: ConfigSchema.option("hide_project_folder")!)
                    Hairline()
                    OptionRow(option: ConfigSchema.option("hide_file_names")!)
                    Hairline()
                    OptionRow(option: ConfigSchema.option("exclude_unknown_project")!)
                    Hairline()
                    OptionRow(option: ConfigSchema.option("status_bar_coding_activity")!)
                }
            }
        default:
            heading("Your dashboard", "Pick the widgets you want. Drag to reorder — you can change this later with Customize.")
            Panel(padding: 0) { CustomizeDashboardSheet(embedded: true) }
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .bold))
            Text(subtitle).font(.studioBody).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EditorsStep: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Panel {
            if let status = model.vscodeStatus {
                if !status.isAppInstalled {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusLine(status: .info, title: "VS Code isn’t installed",
                                   detail: "Install VS Code, or set up your editor manually using Hackatime’s guides — your config is already in place.")
                        Link("Hackatime editor guides", destination: URL(string: "https://hackatime.hackclub.com/docs")!)
                    }
                } else if let ext = model.vscode.recommendedExtension {
                    let installed = model.vscode.knownExtensions.filter { $0.role != .unofficial && status.isInstalled($0.id) }
                    HStack(alignment: .center) {
                        StatusLine(status: installed.isEmpty ? .warning : .ok,
                                   title: installed.isEmpty ? "\(ext.name) isn’t installed" : "\(installed.map(\.name).joined(separator: ", ")) installed",
                                   detail: installed.isEmpty ? "VS Code \(status.appVersion ?? "") was found." : "It will use the API key Studio just saved.\(status.isRunning ? " Reload the VS Code window if you just installed it." : "")")
                        Spacer()
                        if installed.isEmpty {
                            if model.editorBusy == ext.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Open in VS Code") { model.vscode.openExtensionPage(ext) }.buttonStyle(.studioQuiet)
                                Button("Install") { Task { await model.install(ext) } }.buttonStyle(.studioPrimary)
                                    .disabled(status.cliURL == nil)
                            }
                        }
                    }
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Checking VS Code…").foregroundStyle(Theme.inkSecondary) }
                    .task { await model.refreshEditors() }
            }
        }
    }
}

private struct FoldersStep: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.folderRoots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((root as NSString).lastPathComponent).font(.studioBody.weight(.medium))
                            Text(StudioPaths.abbreviate(root)).font(.studioCode).foregroundStyle(Theme.inkTertiary)
                        }
                        Spacer()
                        FolderModeMenu(mode: model.mode(for: root), onChange: { model.setMode($0, for: root) },
                                       defaultName: (root as NSString).lastPathComponent)
                    }
                    Hairline()
                }
                if model.folderRoots.isEmpty {
                    UnavailableNote(symbol: "folder", text: "No folders yet. Without rules, projects are detected from git repositories and the folder you open in VS Code.")
                }
                Button {
                    for url in FilePicker.chooseFolder(message: "Choose folders that contain your projects", multiple: true) {
                        model.addWorkingFolder(url)
                    }
                } label: { Label("Add folder…", systemImage: "folder.badge.plus") }
                .buttonStyle(.studioSecondary)
                Text("Tip: for a folder full of separate projects (like ~/Desktop/Hack Club), choose “Each sub-folder is a project”. Fine-tune individual sub-folders on the Folders & Projects page.")
                    .font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
