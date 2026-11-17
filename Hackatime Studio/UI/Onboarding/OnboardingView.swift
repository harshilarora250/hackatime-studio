import SwiftUI

/// First-run experience: one required input (the API key), then an optional guided setup.
struct OnboardingView: View {
    var flow: SetupFlow
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            Group {
                switch flow {
                case .enterKey: KeyStep()
                case .success: SuccessStep()
                case .guided(let step): GuidedSetupView(step: step)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .overlay(alignment: .topTrailing) {
            if flow == .enterKey && model.apiKey != nil || flow != .enterKey {
                Button("Close") { model.finishSetup() }.buttonStyle(.studioQuiet).padding(16)
            }
        }
    }
}

private struct Brand: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent)
                Image(systemName: "clock.badge.checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.accentInk)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 0) {
                Text("Hackatime").font(.system(size: 20, weight: .bold))
                Text("Studio").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hackatime Studio")
    }
}

private struct KeyStep: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var checking = false
    @State private var result: AppModel.KeyValidation?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Brand()
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect to Hackatime").font(.system(size: 26, weight: .bold))
                Text("Paste your API key. Studio verifies it with Hackatime, then saves it to the config file your editors already read.")
                    .font(.studioBody).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }

            existingConfigNote

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("Your Hackatime API key", text: $key)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .focused($focused)
                        .onSubmit { Task { await verify() } }
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.well, style: .continuous)
                            .strokeBorder(focused ? Theme.accent : Theme.hairline, lineWidth: focused ? 1.5 : 1))
                    Button("Paste") { key = Pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                        .buttonStyle(.studioSecondary)
                }
                Link("Find your key in Hackatime settings ↗", destination: URL(string: "https://hackatime.hackclub.com/my/settings")!)
                    .font(.studioCallout)
            }

            feedback

            HStack {
                Spacer()
                Button { Task { await verify() } } label: {
                    HStack(spacing: 8) {
                        if checking { ProgressView().controlSize(.small) }
                        Text(checking ? "Verifying…" : "Verify & continue")
                    }
                    .frame(minWidth: 150)
                }
                .buttonStyle(.studioPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || checking)
            }
        }
        .padding(36)
        .frame(width: 520)
        .background(Theme.panel.opacity(0.0))
        .onAppear { focused = true }
    }

    @ViewBuilder private var existingConfigNote: some View {
        if model.location.exists {
            let count = model.document?.lines.filter { if case .entry = $0 { return true }; return false }.count ?? 0
            StatusLine(status: .info, title: "Found \(model.location.displayPath)",
                       detail: "\(count) existing setting\(count == 1 ? "" : "s") will be kept. Studio only adds what’s missing.")
        } else {
            StatusLine(status: .info, title: "No config yet",
                       detail: "Studio will create \(model.location.displayPath) with your key and Hackatime’s API URL.")
        }
        if let url = model.configuredAPIURL, HackatimeEndpoints(apiURL: url)?.looksLikeWakaTime == true {
            StatusLine(status: .warning, title: "Your config points to WakaTime",
                       detail: "api_url will be switched to \(ConfigSchema.hackatimeAPIURL) so heartbeats reach Hackatime.")
        }
    }

    @ViewBuilder private var feedback: some View {
        switch result {
        case .invalid:
            StatusLine(status: .error, title: "That key wasn’t accepted",
                       detail: "Hackatime returned “unauthorized”. Copy the key again — it may have been rotated. Nothing was saved.")
        case .unreachable(let why):
            HStack(alignment: .top) {
                StatusLine(status: .warning, title: "Couldn’t reach Hackatime", detail: why)
                Spacer()
                Button("Save anyway") { save(nil) }.buttonStyle(.studioSecondary)
            }
        default: EmptyView()
        }
    }

    private func verify() async {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        checking = true
        result = await model.check(key: k)
        checking = false
        if case .valid(let profile) = result { save(profile) }
    }

    private func save(_ profile: UserProfile?) {
        if model.saveAPIKey(key, profile: profile) {
            withAnimation(Theme.Motion.page) { model.setupFlow = .success }
        }
    }
}

private struct SuccessStep: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle().fill(Theme.ok.opacity(0.14)).frame(width: 84, height: 84)
                Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.ok)
                    .scaleEffect(appeared ? 1 : 0.4).opacity(appeared ? 1 : 0)
            }
            VStack(spacing: 8) {
                Text("You’re set up.").font(.system(size: 28, weight: .bold))
                Text(subtitle).font(.studioBody).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            }
            HStack(alignment: .top, spacing: 14) {
                choice("Guided setup", "Editor, folders, privacy and your dashboard — about two minutes.", "list.number", primary: true) {
                    withAnimation(Theme.Motion.page) { model.setupFlow = .guided(0) }
                }
                choice("Manual configuration", "Go straight to every option in the configuration centre.", "slider.horizontal.3") {
                    model.route = .configuration; model.finishSetup()
                }
                choice("Skip for now", "Open the dashboard. You can run setup later from Settings.", "arrow.right.circle") {
                    model.route = .dashboard; model.finishSetup()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(36)
        .frame(maxWidth: 760)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.1)) { appeared = true } }
    }

    private var subtitle: String {
        let who = model.connection.profile.map { "Signed in as \($0.username.map { "@\($0)" } ?? $0.bestName). " } ?? ""
        return who + "Your key and Hackatime’s API URL are saved in \(model.location.displayPath)."
    }

    private func choice(_ title: String, _ detail: String, _ symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(primary ? Theme.accentInk : Theme.accent)
                Text(title).font(.studioHeadline).foregroundStyle(primary ? Theme.accentInk : Theme.ink)
                Text(detail).font(.studioCallout).foregroundStyle(primary ? Theme.accentInk.opacity(0.85) : Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(primary ? Theme.accent : Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(primary ? .clear : Theme.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1).animation(Theme.Motion.hover, value: configuration.isPressed)
    }
}
