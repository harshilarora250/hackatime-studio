import AVKit
import SwiftUI

/// Your Lapse timelapses from the past 7 days: watch them in Studio or download the video files.
struct LapseView: View {
    @Environment(AppModel.self) private var model
    @State private var playing: LapseTimelapse?

    private var store: LapseStore { model.lapse }

    var body: some View {
        Page {
            PageHeader(title: "Lapse", subtitle: "Your public timelapses from the past 7 days, from lapse.hackclub.com.") {
                HStack(spacing: 8) {
                    if let url = store.user?.profileURL ?? URL(string: "https://lapse.hackclub.com") {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Label(store.user == nil ? "Open Lapse" : "Open profile", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.studioSecondary)
                    }
                    IconButton(symbol: "arrow.clockwise", label: "Reload timelapses", spinning: store.isLoading) {
                        Task { await model.refreshLapse(force: true) }
                    }
                    .disabled(store.isLoading)
                }
            }

            content
        }
        .task(id: model.hackatimeUserID) { await model.refreshLapse() }
        .sheet(item: $playing) { timelapse in
            LapsePlayerSheet(timelapse: timelapse) { playing = nil }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading where store.user == nil:
            Panel {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking up your Lapse profile…").font(.studioBody).foregroundStyle(Theme.inkSecondary)
                }
            }
        case .needsHackatime:
            notice(status: .warning, title: "Connect Hackatime first",
                   detail: "Studio finds your Lapse profile through your Hackatime account. Add a working API key, then come back.",
                   action: ("Open Configuration", { model.route = .configuration }))
        case .notOnLapse:
            notice(status: .unknown, title: "No Lapse profile is linked to this Hackatime account",
                   detail: "Sign in to Lapse with Hackatime once to create one. Your published timelapses will show up here.",
                   action: ("Open lapse.hackclub.com", { NSWorkspace.shared.open(URL(string: "https://lapse.hackclub.com")!) }))
        case .failed(let message) where store.user == nil:
            notice(status: .error, title: "Couldn’t load your timelapses", detail: message,
                   action: ("Try again", { Task { await model.refreshLapse(force: true) } }))
        default:
            loaded
        }
    }

    @ViewBuilder private var loaded: some View {
        if case .failed(let message) = store.phase {
            Panel(padding: 12) { StatusLine(status: .warning, title: "Showing the last timelapses Studio loaded", detail: message) }
        }
        if let user = store.user { profileStrip(user) }

        let recent = store.recent
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Past 7 days",
                          subtitle: recent.isEmpty ? nil : "\(recent.count) timelapse\(recent.count == 1 ? "" : "s") · \(Formatters.duration(recent.reduce(0) { $0 + $1.duration })) recorded")
            if recent.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        UnavailableNote(symbol: "film", text: emptyText)
                        if let latest = store.all.first {
                            Button { NSWorkspace.shared.open(latest.webURL ?? URL(string: "https://lapse.hackclub.com")!) } label: {
                                Label("Watch “\(latest.name)” on Lapse", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.studio(.quiet, compact: true))
                        }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 400), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(recent) { timelapse in
                        LapseCard(timelapse: timelapse, state: store.downloads[timelapse.id],
                                  onPlay: { playing = timelapse },
                                  onDownload: { store.download(timelapse) },
                                  onCancel: { store.cancelDownload(timelapse.id) },
                                  onReveal: { store.revealDownload(timelapse.id) })
                    }
                }
            }
        }

        UnavailableNote(symbol: "lock",
                        text: "Unlisted timelapses and unpublished drafts aren’t shown. Lapse only shares them after you sign in to Lapse itself, and your Hackatime API key can’t do that.")
    }

    private var emptyText: String {
        guard let latest = store.all.first else { return "You haven’t published any public timelapses yet." }
        return "No public timelapses in the past 7 days. Your latest was published \(Formatters.relative(latest.createdAt))."
    }

    private func profileStrip(_ user: LapseUser) -> some View {
        Panel(padding: 14) {
            HStack(spacing: 12) {
                AsyncImage(url: user.profilePictureUrl.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Theme.inkTertiary)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName).font(.studioHeadline).foregroundStyle(Theme.ink)
                    Text("@\(user.handle)").font(.studioCode).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(store.all.count)").font(.studioMetricSmall).foregroundStyle(Theme.ink).contentTransition(.numericText())
                    Text("public timelapses in total").font(.studioCaption).foregroundStyle(Theme.inkTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func notice(status: DiagnosticCheck.Status, title: String, detail: String, action: (String, () -> Void)) -> some View {
        Panel {
            HStack(alignment: .top, spacing: 12) {
                StatusLine(status: status, title: title, detail: detail)
                Spacer(minLength: 12)
                Button(action.0, action: action.1).buttonStyle(.studio(.primary, compact: true))
            }
        }
    }
}

// MARK: - Card

private struct LapseCard: View {
    var timelapse: LapseTimelapse
    var state: LapseStore.DownloadState?
    var onPlay: () -> Void
    var onDownload: () -> Void
    var onCancel: () -> Void
    var onReveal: () -> Void
    @State private var hovering = false

    var body: some View {
        Panel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail.layoutPriority(1) // size by width first, so it spans the card
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(timelapse.name).font(.studioHeadline).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(timelapse.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                            .font(.studioCaption).foregroundStyle(Theme.inkTertiary)
                            .help(Formatters.relative(timelapse.createdAt))
                    }
                    if !timelapse.description.isEmpty {
                        Text(timelapse.description).font(.studioCallout).foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2, reservesSpace: true)
                    }
                    if let blocker = timelapse.blocker {
                        UnavailableNote(symbol: "exclamationmark.triangle", text: "Withheld by Lapse staff: \(blocker)")
                    }
                    Spacer(minLength: 0)
                    actions
                }
                .padding(14)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .studioAppear()
    }

    private var thumbnail: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(Theme.panelRaised)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: timelapse.thumbnailURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "film").font(.system(size: 22)).foregroundStyle(Theme.inkTertiary)
                        }
                    }
                    .clipped()
                    .overlay {
                        Image(systemName: timelapse.isProcessing ? "hourglass" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(hovering ? 0.6 : 0.4), in: Circle())
                            .opacity(hovering || timelapse.isProcessing ? 1 : 0.85)
                    }
                Text(Self.clock(timelapse.duration))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .padding(8)
                    .help("Time recorded")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(timelapse.isProcessing)
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .help(timelapse.isProcessing ? "Lapse is still processing this video" : "Play “\(timelapse.name)”")
        .accessibilityLabel(timelapse.isProcessing ? "\(timelapse.name), still processing" : "Play \(timelapse.name), \(Formatters.longDuration(timelapse.duration)) recorded")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            switch state {
            case .downloading(let fraction):
                ProgressView(value: fraction).progressViewStyle(.linear).frame(maxWidth: .infinity)
                    .accessibilityLabel("Downloading, \(Int(fraction * 100)) percent")
                Text(fraction > 0 ? Formatters.percent(fraction * 100) : "Starting…")
                    .font(.studioCaption.monospacedDigit()).foregroundStyle(Theme.inkSecondary)
                IconButton(symbol: "xmark", label: "Cancel download", action: onCancel)
            case .finished:
                Button(action: onReveal) { Label("Show in Finder", systemImage: "folder") }
                    .buttonStyle(.studio(.secondary, compact: true))
                Spacer(minLength: 0)
                IconButton(symbol: "arrow.down.circle", label: "Download again", action: onDownload)
            default:
                Button(action: onDownload) {
                    Label(state == nil ? "Download" : "Retry download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.studio(.secondary, compact: true))
                .disabled(timelapse.isProcessing)
                Spacer(minLength: 0)
            }
            if let web = timelapse.webURL {
                IconButton(symbol: "arrow.up.right.square", label: "Open on lapse.hackclub.com") { NSWorkspace.shared.open(web) }
            }
        }
    }

    /// 202 → "3:22", 3725 → "1:02:05".
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Player

private struct LapsePlayerSheet: View {
    var timelapse: LapseTimelapse
    var close: () -> Void
    @Environment(AppModel.self) private var model
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timelapse.name).font(.studioHeadline).foregroundStyle(Theme.ink)
                    Text("\(Formatters.relative(timelapse.createdAt)) · \(Formatters.duration(timelapse.duration)) recorded")
                        .font(.studioCaption).foregroundStyle(Theme.inkTertiary)
                }
                Spacer()
                Button { model.lapse.download(timelapse) } label: { Label("Download", systemImage: "arrow.down.circle") }
                    .buttonStyle(.studio(.secondary, compact: true))
                    .disabled(model.lapse.downloads[timelapse.id]?.isActive == true)
                Button("Done", action: close).buttonStyle(.studio(.primary, compact: true)).keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Hairline()
            ZStack {
                Color.black
                if let player { VideoPlayer(player: player) }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
        .frame(minWidth: 720, idealWidth: 960)
        .background(Theme.panel)
        .onAppear {
            guard let url = timelapse.playbackURL else { return }
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear { player?.pause(); player = nil }
    }
}
