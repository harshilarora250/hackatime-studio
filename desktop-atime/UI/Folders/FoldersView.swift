import SwiftUI

struct FoldersView: View {
    @Environment(AppModel.self) private var model
    @State private var showHow = false

    var body: some View {
        Page {
            PageHeader(title: "Folders & Projects",
                       subtitle: "Decide how your folders become Hackatime projects. Rules are written to [projectmap] and exclude.") {
                Button { addFolders() } label: { Label("Add folder…", systemImage: "folder.badge.plus") }
                    .buttonStyle(.studioPrimary)
            }

            howItWorks

            if model.folderRoots.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        UnavailableNote(symbol: "folder", text: "No working folders yet. Add the folders you code in — for example ~/Desktop/Hack Club or ~/Documents/Projects — then choose how each one should be interpreted.")
                        Button { addFolders() } label: { Label("Add folder…", systemImage: "folder.badge.plus") }
                            .buttonStyle(.studioSecondary)
                    }
                }
            } else {
                ForEach(model.folderRoots, id: \.self) { root in
                    FolderPanel(root: root)
                }
            }

            customRules

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Detection options")
                Panel {
                    VStack(spacing: 0) {
                        OptionRow(option: ConfigSchema.option("include_only_with_project_file")!)
                        Hairline()
                        OptionRow(option: ConfigSchema.option("exclude_unknown_project")!)
                        Hairline()
                        OptionRow(option: ConfigSchema.option("project_from_git_remote", section: "git")!)
                    }
                }
            }
        }
    }

    private var howItWorks: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(Theme.Motion.appear) { showHow.toggle() } } label: {
                    HStack {
                        Image(systemName: "lightbulb").foregroundStyle(Theme.accent)
                        Text("How wakatime-cli picks a project name").font(.studioHeadline).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(showHow ? 180 : 0)).foregroundStyle(Theme.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showHow {
                    VStack(alignment: .leading, spacing: 6) {
                        step(1, "A .wakatime-project file in the folder or any parent folder — always wins.")
                        step(2, "A [projectmap] rule — what Studio writes for the folders below.")
                        step(3, "The git repository the file is in (its folder name, or the remote name if enabled).")
                        step(4, "Otherwise, the folder you opened in VS Code.")
                        Text("Excluded paths are never sent. Rules apply to every editor that uses wakatime-cli, from the next heartbeat — no restart needed. wakatime-cli loads [projectmap] rules in no fixed order, so Studio writes rules that never overlap.")
                            .font(.studioCallout).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18).background(Theme.accentSoft, in: Circle())
            Text(text).font(.studioCallout).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var customRules: some View {
        let rules = model.projectRules
        if !rules.customMapEntries.isEmpty || !rules.customExcludes.isEmpty || !rules.legacyIgnore.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Your own rules", subtitle: "Patterns written by hand. Studio leaves them untouched.") {
                    Button("Edit in Advanced") { model.route = .configuration }.buttonStyle(.studioQuiet)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rules.customMapEntries) { e in
                            ruleLine("projectmap", "\(e.key) → \(e.value)")
                        }
                        ForEach(rules.customExcludes, id: \.self) { ruleLine("exclude", $0) }
                        ForEach(rules.legacyIgnore, id: \.self) { ruleLine("ignore", $0) }
                    }
                }
            }
        }
    }

    private func ruleLine(_ key: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            KeyTag(key: key)
            Text(text).font(.studioCode).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }

    private func addFolders() {
        for url in FilePicker.chooseFolder(message: "Choose folders that contain your projects", multiple: true) {
            model.addWorkingFolder(url)
        }
    }
}

/// Menu for choosing a folder mode.
struct FolderModeMenu: View {
    var mode: FolderMode
    var isChild = false
    var onChange: (FolderMode) -> Void
    var defaultName: String

    var body: some View {
        Menu {
            Button { onChange(.automatic) } label: { menuLabel(isChild ? "Automatic (inherit)" : "Automatic", "wand.and.stars", selected: mode == .automatic) }
            Button { onChange(.eachSubfolder) } label: { menuLabel("Each sub-folder is a project", "square.grid.2x2", selected: mode == .eachSubfolder) }
            Button {
                if case .singleProject = mode {} else { onChange(.singleProject(defaultName)) }
            } label: { menuLabel("One project", "shippingbox", selected: { if case .singleProject = mode { return true }; return false }()) }
            Divider()
            Button { onChange(.excluded) } label: { menuLabel("Exclude from tracking", "eye.slash", selected: mode == .excluded) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(mode.title)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.button)
        .fixedSize()
        .help("How wakatime-cli should treat this folder")
    }

    private var symbol: String {
        switch mode {
        case .automatic: "wand.and.stars"
        case .eachSubfolder: "square.grid.2x2"
        case .singleProject: "shippingbox"
        case .excluded: "eye.slash"
        }
    }

    @ViewBuilder private func menuLabel(_ title: String, _ symbol: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Label(title, systemImage: symbol) }
    }
}

private struct FolderPanel: View {
    var root: String
    @Environment(AppModel.self) private var model
    @State private var insights: [FolderInsight] = []
    @State private var loading = true
    @State private var rootInsight: FolderInsight?
    @State private var showAll = false

    private var url: URL { URL(fileURLWithPath: root, isDirectory: true) }
    private var exists: Bool { FileManager.default.fileExists(atPath: root) }

    var body: some View {
        let mode = model.mode(for: root)
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: mode == .excluded ? "folder.badge.minus" : "folder.fill")
                        .font(.system(size: 20)).foregroundStyle(mode == .excluded ? Theme.inkTertiary : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.studioHeadline)
                        Text(StudioPaths.abbreviate(root)).font(.studioCode).foregroundStyle(Theme.inkTertiary)
                    }
                    Spacer()
                    FolderModeMenu(mode: mode, onChange: { model.setMode($0, for: root) }, defaultName: url.lastPathComponent)
                    IconButton(symbol: "arrow.up.forward.app", label: "Show in Finder") { model.perform(.reveal(url)) }
                    IconButton(symbol: "trash", label: "Remove folder and its rules") { model.removeWorkingFolder(root) }
                }

                if !exists {
                    StatusLine(status: .warning, title: "Folder not found", detail: "Rules for it stay in your config until you remove them.")
                }

                modeExplanation(mode)

                if case .singleProject(let name) = mode {
                    ProjectNameField(name: name) { model.setMode(.singleProject($0), for: root) }
                }

                if mode != .excluded && exists {
                    Hairline()
                    children(parentMode: mode)
                }
            }
        }
        .task(id: TaskKey(root: root, document: model.document)) { await load() }
    }

    private struct TaskKey: Equatable { var root: String; var document: INIDocument? }

    @ViewBuilder private func modeExplanation(_ mode: FolderMode) -> some View {
        let text: String = switch mode {
        case .automatic: "No rule. Projects inside are detected normally — usually from their git repository."
        case .eachSubfolder: "Every direct sub-folder is its own project, named after the folder — even without git."
        case .singleProject: "Everything inside counts as one project."
        case .excluded: "Nothing inside this folder is tracked."
        }
        Text(text).font(.studioCallout).foregroundStyle(Theme.inkSecondary)
    }

    @ViewBuilder private func children(parentMode: FolderMode) -> some View {
        if loading {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Scanning…").font(.studioCallout).foregroundStyle(Theme.inkSecondary) }
        } else if insights.isEmpty {
            UnavailableNote(symbol: "folder", text: "No sub-folders.")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Eyebrow("Sub-folder")
                    Spacer()
                    Eyebrow("Will be tracked as")
                        .frame(width: 260, alignment: .leading)
                    Color.clear.frame(width: 150)
                }
                .padding(.horizontal, 8)
                ForEach(showAll ? insights : Array(insights.prefix(25))) { insight in
                    ChildRow(insight: insight)
                }
                if insights.count > 25 {
                    Button(showAll ? "Show fewer" : "Show all \(insights.count)") { showAll.toggle() }.buttonStyle(.studioQuiet)
                }
            }
        }
    }

    private func load() async {
        let doc = model.document ?? INIDocument()
        let folder = url
        let result = await Task.detached(priority: .userInitiated) {
            ProjectResolver.children(of: folder).map { ProjectResolver.insight(for: $0, document: doc) }
        }.value
        insights = result
        loading = false
    }
}

private struct ChildRow: View {
    var insight: FolderInsight
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let mode = model.mode(for: insight.url.path)
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(insight.name).font(.studioBody).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                if insight.isGitRepository { badge("git") }
                if insight.hasProjectFile { badge(".wakatime-project") }
                if insight.hasLocalConfig { badge(".wakatime") }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if !insight.ambiguousPatterns.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                            .help("Several [projectmap] rules match with different names; wakatime-cli picks one unpredictably.")
                    }
                    Text(insight.projectName ?? (isExcluded ? "Not tracked" : "Depends on editor"))
                        .font(.studioCode)
                        .foregroundStyle(insight.projectName == nil ? Theme.inkTertiary : Theme.ink)
                        .lineLimit(1)
                }
                Text(insight.explanation).font(.studioCaption).foregroundStyle(Theme.inkTertiary).lineLimit(1)
            }
            .frame(width: 260, alignment: .leading)
            FolderModeMenu(mode: mode, isChild: true, onChange: { model.setMode($0, for: insight.url.path) }, defaultName: insight.name)
                .controlSize(.small)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(hovering ? Theme.panelRaised : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .contextMenu {
            Button("Show in Finder") { model.perform(.reveal(insight.url)) }
            if case .projectFile(let f) = insight.source { Button("Reveal .wakatime-project") { model.perform(.reveal(f)) } }
        }
    }

    private var isExcluded: Bool {
        if case .excluded = insight.source { return true }
        if case .notTracked = insight.source { return true }
        return false
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.hairline))
    }
}

private struct ProjectNameField: View {
    var name: String
    var commit: (String) -> Void
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Project name").font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                TextField("Project name", text: $text).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                    .onSubmit(save)
                Button("Save", action: save).buttonStyle(.studio(.secondary, compact: true)).disabled(text == name)
            }
            if let error { Text(error).font(.studioCaption).foregroundStyle(Theme.error) }
        }
        .onAppear { text = name }
        .onChange(of: name) { _, n in text = n }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { error = "Enter a name."; return }
        if t.contains("#") || t.contains(";") { error = "Names can’t contain # or ; (they start a comment in the config)."; return }
        error = nil
        commit(t)
    }
}
