import Foundation

nonisolated enum HackatimeAPIError: LocalizedError, Equatable {
    case noAPIKey
    case invalidAPIURL(String)
    case unauthorized
    case forbidden(String?)
    case notFound(String)
    case rateLimited
    case server(Int)
    case offline
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No API key is configured."
        case .invalidAPIURL(let u): "“\(u)” isn’t a valid API URL."
        case .unauthorized: "Hackatime rejected the API key. It may have been rotated or mistyped — copy it again from hackatime.hackclub.com/my/settings."
        case .forbidden(let why): "Hackatime refused the request\(why.map { ": \($0)" } ?? ".")"
        case .notFound(let path): "This Hackatime server doesn’t provide \(path). Is the API URL pointing at Hackatime?"
        case .rateLimited: "Hackatime is rate-limiting requests. Studio will retry later."
        case .server(let code): "Hackatime returned a server error (HTTP \(code)). Try again in a moment."
        case .offline: "You appear to be offline."
        case .network(let why): "Couldn’t reach Hackatime: \(why)"
        case .decoding(let what): "Hackatime sent a response Studio couldn’t read (\(what))."
        }
    }

    /// True when the key itself is the problem (vs. connectivity).
    var isCredentialProblem: Bool { self == .unauthorized || self == .noAPIKey }
}

/// Endpoints derived from the configured `api_url`.
nonisolated struct HackatimeEndpoints: Equatable, Sendable {
    /// e.g. https://hackatime.hackclub.com/api/hackatime/v1 (WakaTime-compatible namespace)
    var compatBase: URL
    /// e.g. https://hackatime.hackclub.com
    var root: URL

    init?(apiURL: String) {
        var trimmed = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http"), let host = url.host() else { return nil }
        compatBase = url
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        guard let root = components.url else { return nil }
        self.root = root
    }

    var isOfficialHackatime: Bool { root.host() == "hackatime.hackclub.com" }
    var looksLikeWakaTime: Bool { root.host()?.hasSuffix("wakatime.com") == true }
    var dashboardURL: URL { root }
}

/// Thin, stateless client for the Hackatime endpoints that accept an API key.
/// The key is only ever placed in the `Authorization` header — never in URLs or logs.
nonisolated struct HackatimeClient: Sendable {
    let endpoints: HackatimeEndpoints
    private let apiKey: String
    private let session: URLSession

    init(apiURL: String, apiKey: String, session: URLSession = .shared) throws {
        guard let endpoints = HackatimeEndpoints(apiURL: apiURL) else { throw HackatimeAPIError.invalidAPIURL(apiURL) }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw HackatimeAPIError.noAPIKey }
        self.endpoints = endpoints
        self.apiKey = key
        self.session = session
    }

    // MARK: Endpoints

    func currentUser() async throws -> UserProfile {
        try await get(endpoints.compatBase.appending(path: "users/current"), as: DataEnvelope<UserProfile>.self).data
    }

    func statusBarToday() async throws -> StatusBarToday {
        try await get(endpoints.compatBase.appending(path: "users/current/statusbar/today"), as: DataEnvelope<StatusBarToday>.self).data
    }

    /// Daily totals (and per-day projects). The server caps a request at 366 days.
    func summaries(from start: String, to end: String) async throws -> [DailySummary] {
        var c = URLComponents(url: endpoints.compatBase.appending(path: "users/current/summaries"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "start", value: start), .init(name: "end", value: end)]
        return try await get(c.url!, as: SummariesResponse.self).data
    }

    func stats(from start: Date, to end: Date, limit: Int = 0) async throws -> UserStats {
        var c = URLComponents(url: endpoints.root.appending(path: "api/v1/users/my/stats"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "features", value: "languages,projects"),
            .init(name: "start_date", value: Self.iso.string(from: start)),
            .init(name: "end_date", value: Self.iso.string(from: end)),
        ]
        if limit > 0 { items.append(.init(name: "limit", value: String(limit))) }
        c.queryItems = items
        return try await get(c.url!, as: DataEnvelope<UserStats>.self).data
    }

    func spans(from start: Date, to end: Date) async throws -> [ActivitySpan] {
        var c = URLComponents(url: endpoints.root.appending(path: "api/v1/users/my/heartbeats/spans"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "start_date", value: Self.iso.string(from: start)),
                        .init(name: "end_date", value: Self.iso.string(from: end))]
        return try await get(c.url!, as: SpansResponse.self).spans
    }

    func mostRecentHeartbeat(editor: String? = nil) async throws -> MostRecentHeartbeatResponse {
        var c = URLComponents(url: endpoints.root.appending(path: "api/v1/my/heartbeats/most_recent"), resolvingAgainstBaseURL: false)!
        if let editor { c.queryItems = [.init(name: "editor", value: editor)] }
        return try await get(c.url!, as: MostRecentHeartbeatResponse.self)
    }

    // MARK: Transport

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HackatimeStudio/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw HackatimeAPIError.offline
            case .cancelled: throw CancellationError()
            default: throw HackatimeAPIError.network(error.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw HackatimeAPIError.network("no HTTP response") }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw HackatimeAPIError.unauthorized
        case 403: throw HackatimeAPIError.forbidden(Self.errorMessage(in: data))
        case 404: throw HackatimeAPIError.notFound(url.path())
        case 429: throw HackatimeAPIError.rateLimited
        default: throw HackatimeAPIError.server(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HackatimeAPIError.decoding(String(describing: T.self))
        }
    }

    private static func errorMessage(in data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["error"] as? String) ?? (obj["message"] as? String)
    }
}
