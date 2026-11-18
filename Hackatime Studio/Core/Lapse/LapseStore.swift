import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// State for the Lapse page: the linked Lapse profile, its recent public timelapses, and downloads.
@MainActor
@Observable
final class LapseStore {

    enum Phase: Equatable {
        case idle
        case loading
        /// Hackatime hasn't told us who the user is yet (no key, or the key isn't verified).
        case needsHackatime
        /// The Hackatime user has never signed in to Lapse.
        case notOnLapse
        case loaded
        case failed(String)
    }

    enum DownloadState: Equatable {
        case downloading(Double)
        case finished(URL)
        case failed(String)

        var isActive: Bool { if case .downloading = self { true } else { false } }
    }

    /// How far back the page looks.
    static let window: TimeInterval = 7 * 24 * 60 * 60

    private(set) var phase: Phase = .idle
    private(set) var user: LapseUser?
    /// Every public timelapse, newest first. `recent` is the slice shown on the page.
    private(set) var all: [LapseTimelapse] = []
    private(set) var fetchedAt: Date?
    private(set) var downloads: [LapseTimelapse.ID: DownloadState] = [:]
    private var loadedFor: String?
    private var tasks: [LapseTimelapse.ID: URLSessionDownloadTask] = [:]

    /// Set by `AppModel` so downloads can report through the app-wide toast.
    var notify: (Toast) -> Void = { _ in }

    let client: LapseClient

    init(client: LapseClient = LapseClient()) {
        self.client = client
    }

    var recent: [LapseTimelapse] {
        let cutoff = (fetchedAt ?? Date()).addingTimeInterval(-Self.window)
        return all.filter { $0.createdAt >= cutoff }
    }

    var isLoading: Bool { phase == .loading }

    /// Loads once per Hackatime user; `force` reloads (⌘R, the page's refresh button).
    func refresh(hackatimeID: String?, force: Bool = false) async {
        guard let hackatimeID, !hackatimeID.isEmpty else {
            phase = .needsHackatime
            user = nil; all = []; loadedFor = nil
            return
        }
        if !force, loadedFor == hackatimeID, phase == .loaded || phase == .notOnLapse { return }
        guard phase != .loading else { return }
        if loadedFor != hackatimeID { user = nil; all = [] }
        phase = .loading
        do {
            guard let found = try await client.user(hackatimeID: hackatimeID) else {
                user = nil; all = []
                loadedFor = hackatimeID
                fetchedAt = Date()
                phase = .notOnLapse
                return
            }
            let timelapses = try await client.publicTimelapses(userID: found.id)
            user = found
            all = timelapses
            loadedFor = hackatimeID
            fetchedAt = Date()
            phase = .loaded
        } catch is CancellationError {
            phase = loadedFor == nil ? .idle : .loaded
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Downloads

    /// Asks where to save, then downloads the published video file.
    func download(_ timelapse: LapseTimelapse) {
        guard let source = timelapse.playbackURL, downloads[timelapse.id]?.isActive != true else { return }

        let panel = NSSavePanel()
        panel.title = "Download Timelapse"
        panel.message = "Save “\(timelapse.name)” from Lapse"
        panel.prompt = "Download"
        panel.nameFieldStringValue = timelapse.suggestedFilename
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        let ext = (timelapse.suggestedFilename as NSString).pathExtension
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .movie]
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        downloads[timelapse.id] = .downloading(0)
        let id = timelapse.id
        let name = timelapse.name

        var request = URLRequest(url: source, timeoutInterval: 60)
        request.setValue("HackatimeStudio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.downloadTask(with: request) { location, response, error in
            // The temporary file is deleted when this handler returns, so move it now.
            let outcome = Self.finish(location: location, response: response, error: error, destination: destination)
            Task { @MainActor [weak self] in self?.complete(id: id, name: name, outcome: outcome) }
        }
        tasks[id] = task
        task.resume()

        // Report progress while the task runs.
        Task { [weak self] in
            while let self, case .downloading = self.downloads[id], let task = self.tasks[id] {
                let fraction = task.progress.fractionCompleted
                if fraction.isFinite { self.downloads[id] = .downloading(min(max(fraction, 0), 1)) }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func cancelDownload(_ id: LapseTimelapse.ID) {
        tasks[id]?.cancel()
    }

    func revealDownload(_ id: LapseTimelapse.ID) {
        guard case .finished(let url) = downloads[id] else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            downloads[id] = nil
            notify(Toast(message: "That file has been moved or deleted.", style: .info))
        }
    }

    private func complete(id: LapseTimelapse.ID, name: String, outcome: Result<URL, DownloadFailure>) {
        tasks[id] = nil
        switch outcome {
        case .success(let url):
            downloads[id] = .finished(url)
            notify(Toast(message: "Saved “\(name)” to \(StudioPaths.abbreviate(url.deletingLastPathComponent().path))", style: .success))
        case .failure(.cancelled):
            downloads[id] = nil
        case .failure(.message(let message)):
            downloads[id] = .failed(message)
            notify(Toast(message: "Couldn’t download “\(name)”: \(message)", style: .error))
        }
    }

    enum DownloadFailure: Error, Sendable { case cancelled, message(String) }

    nonisolated private static func finish(location: URL?, response: URLResponse?, error: Error?,
                                           destination: URL) -> Result<URL, DownloadFailure> {
        if let error = error as? URLError, error.code == .cancelled { return .failure(.cancelled) }
        if let error { return .failure(.message(error.localizedDescription)) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return .failure(.message("the server returned HTTP \(http.statusCode)"))
        }
        guard let location else { return .failure(.message("no file was received")) }
        do {
            let fm = FileManager.default
            // The save panel already confirmed replacing an existing file.
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: location)
            } else {
                try fm.moveItem(at: location, to: destination)
            }
            return .success(destination)
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }
}
