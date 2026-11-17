import SwiftUI

/// One schema option: title, key tag, description, and a control matched to its type.
struct OptionRow: View {
    var option: ConfigOption
    var compact = false
    @Environment(AppModel.self) private var model

    private var explicitValue: String? { model.document?.value(section: option.section, key: option.key) }
    private var aliasInUse: String? {
        guard explicitValue == nil else { return nil }
        return option.aliases.first { model.document?.value(section: option.section, key: $0) != nil }
    }
    private var isSet: Bool { explicitValue != nil || aliasInUse != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(option.title).font(.studioBody.weight(.medium)).foregroundStyle(Theme.ink)
                    if isSet {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                            .help("Set in your config file")
                            .accessibilityLabel("Customised")
                    }
                }
                HStack(spacing: 6) {
                    KeyTag(key: option.key, section: option.section)
                    if option.consumer != .cli {
                        Text(option.consumer.rawValue).font(.studioCaption).foregroundStyle(Theme.inkTertiary)
                    }
                    if let d = option.defaultValue, !isSet {
                        Text("default: \(d)").font(.studioCaption).foregroundStyle(Theme.inkTertiary)
                    }
                }
                if !compact {
                    Text(option.summary).font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let alias = aliasInUse {
                    Text("Currently set through the legacy key “\(alias)”, which wakatime-cli still reads. Saving here writes “\(option.key)”, which takes precedence.")
                        .font(.studioCaption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                }
                if isList { listEditor.padding(.top, 4) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isList || option.kind == .boolOrRegexList {
                control
            }
        }
        .padding(.vertical, 10)
    }

    private var isList: Bool {
        switch option.kind {
        case .regexList: return true
        case .boolOrRegexList: return BoolOrListMode(raw: currentValue) == .matching
        default: return false
        }
    }

    private var currentValue: String? { explicitValue ?? aliasInUse.flatMap { model.document?.value(section: option.section, key: $0) } }

    @ViewBuilder private var control: some View {
        switch option.kind {
        case .bool:
            BoolControl(option: option, value: currentValue)
        case .int(let min, let max):
            TextValueControl(option: option, value: currentValue, width: 90) { text in
                guard let n = Int(text) else { return "Enter a whole number." }
                if n < min { return "Must be at least \(min)." }
                if let max, n > max { return "Must be at most \(max)." }
                return nil
            }
        case .string, .url, .path:
            TextValueControl(option: option, value: currentValue, width: 280) { text in
                if option.kind == .url, HackatimeEndpoints(apiURL: text) == nil { return "Enter a full http(s) URL." }
                return nil
            }
        case .secret:
            Text(currentValue.map(Redaction.mask) ?? "Not set").font(.studioCode).foregroundStyle(Theme.inkSecondary)
        case .boolOrRegexList:
            BoolOrListPicker(option: option, value: currentValue)
        case .regexList:
            EmptyView()
        }
    }

    @ViewBuilder private var listEditor: some View {
        PatternListEditor(option: option, value: currentValue)
    }
}

// MARK: - Bool

private struct BoolControl: View {
    var option: ConfigOption
    var value: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        let isOn = (value ?? option.defaultValue ?? "false").lowercased() == "true"
        HStack(spacing: 6) {
            if value != nil {
                Button("Reset") { model.set(option.key, nil, section: option.section) }
                    .buttonStyle(.studio(.quiet, compact: true))
                    .help("Remove from the config and use the default (\(option.defaultValue ?? "unset"))")
            }
            Toggle(option.title, isOn: Binding(
                get: { isOn },
                set: { model.set(option.key, $0 ? "true" : "false", section: option.section) }))
                .toggleStyle(.switch).labelsHidden()
        }
    }
}

// MARK: - Text / number / path

struct TextValueControl: View {
    var option: ConfigOption
    var value: String?
    var width: CGFloat
    var validate: (String) -> String?
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var isNumber: Bool { if case .int = option.kind { return true }; return false }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                TextField(option.defaultValue ?? "Not set", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(isNumber ? .studioBody : .studioCode)
                    .frame(width: width)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, f in if !f { commit() } }
                if option.kind == .path {
                    Button("Choose…") {
                        if let url = FilePicker.chooseFile(message: option.title) { text = url.path; commit() }
                    }
                    .buttonStyle(.studio(.secondary, compact: true))
                }
                if value != nil {
                    Button { text = ""; commit() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.inkTertiary)
                        .help("Remove from config (use default)")
                }
            }
            if let error { Text(error).font(.studioCaption).foregroundStyle(Theme.error) }
        }
        .onAppear { text = value ?? "" }
        .onChange(of: value) { _, v in if !focused { text = v ?? "" } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (value ?? "") else { error = nil; return }
        if trimmed.isEmpty {
            error = nil
            model.set(option.key, nil, section: option.section)
            return
        }
        if let message = validate(trimmed) ?? INIValueRules.singleLineProblem(trimmed) { error = message; return }
        error = nil
        model.set(option.key, trimmed, section: option.section)
    }
}

enum INIValueRules {
    /// go-ini treats the first `#` or `;` in an unquoted single-line value as a comment.
    static func singleLineProblem(_ value: String) -> String? {
        if value.contains("#") || value.contains(";") {
            return "wakatime-cli would cut this value at “#” or “;” (they start a comment)."
        }
        if value.hasSuffix("\\") { return "A trailing “\\” makes go-ini join the next line." }
        return nil
    }
}

// MARK: - Lists

enum BoolOrListMode: Hashable {
    case off, all, matching
    init(raw: String?) {
        let v = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty || v == "false" { self = .off } else if v == "true" { self = .all } else { self = .matching }
    }
}

private struct BoolOrListPicker: View {
    var option: ConfigOption
    var value: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        let mode = BoolOrListMode(raw: value)
        Picker(option.title, selection: Binding(get: { mode }, set: { new in
            switch new {
            case .off: model.set(option.key, value == nil ? nil : "false", section: option.section)
            case .all: model.set(option.key, "true", section: option.section)
            case .matching:
                // Start the list with a harmless placeholder the user then edits.
                model.set(option.key, (option.key == "exclude" ? "^COMMIT_EDITMSG$" : "^/private/") + "\n", section: option.section)
            }
        })) {
            Text(option.key == "exclude" || option.key == "include" ? "None" : "Off").tag(BoolOrListMode.off)
            Text(option.key == "exclude" ? "Everything" : "All").tag(BoolOrListMode.all)
            Text("Matching…").tag(BoolOrListMode.matching)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// Edits a newline-separated list of regexes, stored as a multi-line INI value.
struct PatternListEditor: View {
    var option: ConfigOption
    var value: String?
    var placeholder = "Regex, e.g. /node_modules/"
    @Environment(AppModel.self) private var model
    @State private var newPattern = ""
    @State private var error: String?

    private var items: [String] {
        ProjectRules.listItems(value ?? "").filter { !["true", "false"].contains($0.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            Text(item).font(.studioCode).foregroundStyle(Theme.ink).textSelection(.enabled)
                                .lineLimit(1).truncationMode(.middle)
                            if (try? NSRegularExpression(pattern: item)) == nil {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                                    .help("This doesn’t look like a valid regular expression; wakatime-cli ignores invalid patterns.")
                            }
                            Spacer()
                            Button { remove(at: index) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(Theme.inkTertiary)
                                .help("Remove pattern")
                                .accessibilityLabel("Remove \(item)")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        if index < items.count - 1 { Hairline() }
                    }
                }
                .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous).strokeBorder(Theme.hairline))
            }
            HStack(spacing: 6) {
                TextField(placeholder, text: $newPattern)
                    .textFieldStyle(.roundedBorder).font(.studioCode)
                    .onSubmit(add)
                Button("Add", action: add).buttonStyle(.studio(.secondary, compact: true))
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error { Text(error).font(.studioCaption).foregroundStyle(Theme.error) }
        }
    }

    private func write(_ list: [String]) {
        if list.isEmpty {
            model.set(option.key, option.kind == .boolOrRegexList && value != nil ? "false" : nil, section: option.section)
        } else {
            model.set(option.key, list.joined(separator: "\n") + (list.count == 1 ? "\n" : ""), section: option.section)
        }
    }

    private func add() {
        let p = newPattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        if (try? NSRegularExpression(pattern: p)) == nil { error = "That isn’t a valid regular expression."; return }
        error = nil
        write(items + [p])
        newPattern = ""
    }

    private func remove(at index: Int) {
        var list = items
        list.remove(at: index)
        write(list)
    }
}
