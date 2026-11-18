import Foundation

// Lapse (https://lapse.hackclub.com) is Hack Club's timelapse recorder. Its API
// (https://api.lapse.hackclub.com/api, source: hackclub/lapse) authenticates with its own OAuth
// tokens, not Hackatime API keys, so Studio only uses the public, unauthenticated routes:
//
//   GET /user/query?hackatimeId=N      → the Lapse profile linked to a Hackatime user ID
//   GET /timelapse/findByUser?user=ID  → that user's timelapses (PUBLIC ones only, when unauthenticated)
//
// Published videos are transcoded, unencrypted MP4/WebM files served from a public URL
// (`playbackUrl`). Unlisted timelapses and drafts need a Lapse login and are not shown.
// The Hackatime API key is never sent to Lapse.

nonisolated enum LapseAPIError: LocalizedError, Equatable {
    case api(code: String, message: String?)
    case rateLimited
    case server(Int)
    case offline
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .api(let code, let message): message ?? "Lapse returned an error (\(code))."
        case .rateLimited: "Lapse is rate-limiting requests. Try again in a minute."
        case .server(let code): "Lapse returned a server error (HTTP \(code)). Try again in a moment."
        case .offline: "You appear to be offline."
        case .network(let why): "Couldn’t reach Lapse: \(why)"
        case .decoding: "Lapse sent a response Studio couldn’t read."
        }
    }
}

nonisolated struct LapseUser: Decodable, Hashable, Sendable {
    var id: String
    var handle: String
    var displayName: String
    var profilePictureUrl: String?
    var hackatimeId: String?

    var profileURL: URL? { URL(string: "https://lapse.hackclub.com/user/\(id)") }
}

nonisolated struct LapseTimelapse: Decodable, Hashable, Sendable, Identifiable {
    enum Visibility: String, Decodable, Sendable { case `public` = "PUBLIC", unlisted = "UNLISTED", failed = "FAILED_PROCESSING", unknown }

    var id: String
    var name: String
    var description: String
    var visibility: Visibility
    var createdAt: Date
    /// Time recorded in seconds (from snapshots), not the length of the sped-up video.
    var duration: Double
    var playbackURL: URL?
    var thumbnailURL: URL?
    /// Set when Lapse staff withheld the video; the text explains why. The video can still be watched.
    var blocker: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, visibility, createdAt, duration, blocker
        case playbackURL = "playbackUrl", thumbnailURL = "thumbnailUrl"
    }

    init(id: String, name: String, description: String = "", visibility: Visibility = .public, createdAt: Date,
         duration: Double, playbackURL: URL?, thumbnailURL: URL?, blocker: String? = nil) {
        self.id = id; self.name = name; self.description = description; self.visibility = visibility
        self.createdAt = createdAt; self.duration = duration; self.playbackURL = playbackURL
        self.thumbnailURL = thumbnailURL; self.blocker = blocker
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled timelapse"
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        visibility = (try? c.decode(Visibility.self, forKey: .visibility)) ?? .unknown
        // Lapse dates are milliseconds since the Unix epoch.
        let millis = try c.decode(FlexibleNumber.self, forKey: .createdAt).value
        createdAt = Date(timeIntervalSince1970: millis / 1000)
        duration = (try? c.decode(FlexibleNumber.self, forKey: .duration))?.value ?? 0
        playbackURL = (try? c.decodeIfPresent(String.self, forKey: .playbackURL)).flatMap { $0.flatMap(URL.init(string:)) }
        thumbnailURL = (try? c.decodeIfPresent(String.self, forKey: .thumbnailURL)).flatMap { $0.flatMap(URL.init(string:)) }
        blocker = try? c.decodeIfPresent(String.self, forKey: .blocker)
    }

    /// `playbackUrl` is null while Lapse is still transcoding the video.
    var isProcessing: Bool { playbackURL == nil }
    var webURL: URL? { URL(string: "https://lapse.hackclub.com/timelapse/\(id)") }

    /// A filesystem-safe default name for downloads, e.g. "Hud Framework.mp4".
    var suggestedFilename: String {
        let ext = playbackURL?.pathExtension.lowercased()
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(safe.isEmpty ? id : safe).\(ext == "webm" ? "webm" : "mp4")"
    }
}

/// Lapse wraps every response as `{ ok: true, data }` or `{ ok: false, error, message }`.
nonisolated struct LapseEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    var ok: Bool
    var data: T?
    var error: String?
    var message: String?
}

nonisolated struct LapseUserQuery: Decodable, Sendable { var user: LapseUser? }
nonisolated struct LapseTimelapseList: Decodable, Sendable { var timelapses: [LapseTimelapse] }

nonisolated struct LapseClient: Sendable {
    static let defaultBase = URL(string: "https://api.lapse.hackclub.com/api")!

    var base: URL = Self.defaultBase
    var session: URLSession = .shared

    /// The Lapse account linked to a Hackatime user, or `nil` when they've never signed in to Lapse.
    func user(hackatimeID: String) async throws -> LapseUser? {
        var c = URLComponents(url: base.appending(path: "user/query"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "hackatimeId", value: hackatimeID)]
        return try await get(c.url!, as: LapseUserQuery.self).user
    }

    /// The user's timelapses that are visible without signing in to Lapse (PUBLIC only), newest first.
    func publicTimelapses(userID: String) async throws -> [LapseTimelapse] {
        var c = URLComponents(url: base.appending(path: "timelapse/findByUser"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "user", value: userID)]
        return try await get(c.url!, as: LapseTimelapseList.self).timelapses.sorted { $0.createdAt > $1.createdAt }
    }

    private func get<T: Decodable & Sendable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HackatimeStudio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw LapseAPIError.offline
            case .cancelled: throw CancellationError()
            default: throw LapseAPIError.network(error.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw LapseAPIError.network("no HTTP response") }
        // Lapse reports most failures as JSON with a 4xx status, so try the envelope first.
        let envelope = try? JSONDecoder().decode(LapseEnvelope<T>.self, from: data)
        if let envelope, envelope.ok, let payload = envelope.data { return payload }
        if let envelope, !envelope.ok { throw LapseAPIError.api(code: envelope.error ?? "ERROR", message: envelope.message) }
        switch http.statusCode {
        case 429: throw LapseAPIError.rateLimited
        case 500...: throw LapseAPIError.server(http.statusCode)
        default: throw LapseAPIError.decoding
        }
    }
}
